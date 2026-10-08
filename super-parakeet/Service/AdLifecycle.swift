import Foundation

/// All callers and injected callbacks must execute on the main thread.
/// The SDK adapter dispatches arbitrary load/delegate callbacks to that thread.
final class FullScreenAdGate {
    static let shared = FullScreenAdGate()
    private(set) var flow: UUID?
    private(set) var presentation: UUID?
    func reserveFlow(_ id: UUID) -> Bool {
        guard flow == nil, presentation == nil else { return false }
        flow = id; return true
    }
    func releaseFlow(_ id: UUID) { if flow == id { flow = nil } }
    func claim(_ id: UUID, owner: UUID?) -> Bool {
        guard presentation == nil, flow == owner else { return false }
        presentation = id; return true
    }
    func release(_ id: UUID) { if presentation == id { presentation = nil } }
}

enum AdLifecycleError: LocalizedError {
    case loadTimeout, unavailable, busy, presentationTimeout
    var errorDescription: String? {
        switch self {
        case .loadTimeout: return "광고 로드 시간이 초과되었습니다. 다시 시도해 주세요."
        case .unavailable: return "현재 광고를 표시할 수 없습니다."
        case .busy: return "다른 광고가 진행 중입니다."
        case .presentationTimeout: return "광고 종료 응답이 지연되고 있습니다. 광고 화면의 닫기 버튼으로 닫아 주세요."
        }
    }
}

typealias AdScheduler = (TimeInterval, @escaping () -> Void) -> (() -> Void)
func scheduleAdTask(after seconds: TimeInterval, action: @escaping () -> Void) -> () -> Void {
    let task = DispatchWorkItem(block: action)
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    return { task.cancel() }
}

/// One load in flight, one consumed ad per presentation, exactly one terminal callback.
/// A watchdog never dismisses SDK-owned UI or advances to another ad over visible UI.
final class AdSlot<Ad> {
    typealias Loader = (@escaping (Result<Ad, Error>) -> Void) -> Void
    private let loader: Loader
    private let schedule: AdScheduler
    private let now: () -> TimeInterval
    private let gate: FullScreenAdGate
    private let expiry: TimeInterval
    private var cached: (Ad, TimeInterval)?
    private var loadID: UUID?
    private var loadWaiters: [(Bool) -> Void] = []
    private var cancelLoadTimer: (() -> Void)?
    private var pendingID: UUID?
    private var pendingOwner: UUID?
    private var currentID: UUID?
    private var cancelPresentationTimer: (() -> Void)?
    private var stopPending: (() -> Void)?
    private(set) var lastError: Error?
    var isReady: Bool { cached.map { now() - $0.1 < expiry } ?? false }
    var isPresenting: Bool { currentID != nil }
    var hasPendingPresentation: Bool { pendingID != nil }

    init(expiry: TimeInterval = 3600, gate: FullScreenAdGate = .shared,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
         schedule: @escaping AdScheduler = scheduleAdTask, loader: @escaping Loader) {
        self.expiry = expiry; self.gate = gate; self.now = now
        self.schedule = schedule; self.loader = loader
    }
    func load(completion: ((Bool) -> Void)? = nil) {
        if isReady { completion?(true); return }
        cached = nil
        if let completion = completion { loadWaiters.append(completion) }
        guard loadID == nil else { return }
        let id = UUID(); loadID = id
        cancelLoadTimer = schedule(30) { [weak self] in
            self?.completeLoad(id, .failure(AdLifecycleError.loadTimeout))
        }
        loader { [weak self] result in self?.completeLoad(id, result) }
    }
    private func completeLoad(_ id: UUID, _ result: Result<Ad, Error>) {
        guard loadID == id else { return } // Ignore late/duplicate response from expired request.
        loadID = nil; cancelLoadTimer?(); cancelLoadTimer = nil
        switch result {
        case .success(let ad): cached = (ad, now()); lastError = nil
        case .failure(let error): cached = nil; lastError = error
        }
        let callbacks = loadWaiters; loadWaiters.removeAll()
        let ready = isReady
        callbacks.forEach { $0(ready) }
    }
    func present(owner: UUID?, canPresent: @escaping (Ad) throws -> Void,
                 isVisible: @escaping () -> Bool,
                 show: @escaping (Ad, @escaping () -> Void, @escaping (Bool) -> Void) -> Void,
                 onReward: @escaping () -> Void = {}, onStall: @escaping (Error) -> Void = { _ in },
                 onEnd: @escaping (Bool) -> Void) {
        guard pendingID == nil, currentID == nil else { lastError = AdLifecycleError.busy; onEnd(false); return }
        let request = UUID(); pendingID = request; pendingOwner = owner
        stopPending = { onEnd(false) }
        load { [weak self] success in
            guard let self = self, self.pendingID == request else { return }
            self.pendingID = nil; self.pendingOwner = nil; self.stopPending = nil
            guard success, let (ad, _) = self.cached else { onEnd(false); return }
            do { try canPresent(ad) } catch { self.cached = nil; self.lastError = error; onEnd(false); return }
            let id = UUID()
            guard self.gate.claim(id, owner: owner) else { self.lastError = AdLifecycleError.busy; onEnd(false); return }
            self.cached = nil // SDK full-screen ads are single-use.
            self.currentID = id
            var rewarded = false
            var rejectLateReward = false
            func end(_ dismissed: Bool) {
                guard self.currentID == id else { return }
                rejectLateReward = !dismissed
                self.currentID = nil; self.cancelPresentationTimer?(); self.cancelPresentationTimer = nil
                self.gate.release(id); onEnd(dismissed)
            }
            func checkMissingDismissal(_ first: Bool) {
                guard self.currentID == id else { return }
                if !isVisible() { self.lastError = AdLifecycleError.presentationTimeout; end(false); return }
                if first { self.lastError = AdLifecycleError.presentationTimeout; onStall(AdLifecycleError.presentationTimeout) }
                self.cancelPresentationTimer = self.schedule(1) { checkMissingDismissal(false) }
            }
            self.cancelPresentationTimer = self.schedule(180) { checkMissingDismissal(true) }
            show(ad, { if !rewarded && !rejectLateReward { rewarded = true; onReward() } }, end)
        }
    }
    func cancelPending(owner: UUID?) {
        guard pendingID != nil, pendingOwner == owner else { return }
        pendingID = nil; pendingOwner = nil
        let callback = stopPending; stopPending = nil; callback?()
        // A shared preload may finish, but it cannot present for a cancelled request.
    }
}

/// Callback tokens prevent duplicate/stale dismiss/fail callbacks from skipping steps.
final class AdSequence {
    private(set) var runID: UUID?
    private(set) var stage = 0
    private var token: UUID?
    private var advance: ((Int, UUID, UUID) -> Void)?
    private var finish: (() -> Void)?
    func start(advance: @escaping (Int, UUID, UUID) -> Void, finish: @escaping () -> Void) -> Bool {
        guard runID == nil else { return false }
        runID = UUID(); stage = 0; self.advance = advance; self.finish = finish
        emit(); return true
    }
    private func emit() {
        guard let runID = runID else { return }
        let token = UUID(); self.token = token; advance?(stage, runID, token)
    }
    func complete(run: UUID, token: UUID) {
        guard runID == run, self.token == token else { return }
        self.token = nil; stage += 1
        if stage == 3 { cancel() } else { emit() }
    }
    func cancel() {
        guard runID != nil else { return }
        runID = nil; token = nil; advance = nil
        let callback = finish; finish = nil; callback?()
    }
}

/// SDK/UI adapter supplies these facts from the original presentation scene only.
/// Unrelated scenes and key-window changes are deliberately absent from this model.
struct AdVisibilityFacts {
    let originalSceneIsForeground: Bool
    let presenterHasModalOrTransition: Bool
    let originalSceneHasNewVisibleWindow: Bool
    var shouldWaitForSDKDismissal: Bool {
        !originalSceneIsForeground || presenterHasModalOrTransition || originalSceneHasNewVisibleWindow
    }
}
