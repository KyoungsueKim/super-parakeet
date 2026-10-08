import Foundation
import Combine
import UIKit

@MainActor
final class RewardedAdFlowCoordinator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String?
    private let rewardedAdManager: RewardedAdManager
    private let rewardedInterstitialAdManager: RewardedInterstitialAdManager
    private let interstitialAdManager: InterstitialAdManager
    private let sequence = AdSequence()
    private var owner: UUID?
    private weak var presentationScene: UIWindowScene?
    private var waitTimer: (() -> Void)?
    private var didShowAnyAd = false
    private var wasCancelled = false
    private var rewardHandlers: [() -> Void] = []
    private var onInterstitialShown: (() -> Void)?
    private var onAllAdsUnavailable: (() -> Void)?
    private var onFlowFinished: (() -> Void)?
    private var onNextAdConsentRequested: ((Int, @escaping (Bool) -> Void) -> Void)?
    private var pendingConsentToken: UUID?

    init(rewardedAdManager: RewardedAdManager? = nil,
         rewardedInterstitialAdManager: RewardedInterstitialAdManager? = nil,
         interstitialAdManager: InterstitialAdManager? = nil) {
        self.rewardedAdManager = rewardedAdManager ?? RewardedAdManager()
        self.rewardedInterstitialAdManager = rewardedInterstitialAdManager ?? RewardedInterstitialAdManager()
        self.interstitialAdManager = interstitialAdManager ?? InterstitialAdManager()
    }
    func preloadAds() {
        precondition(Thread.isMainThread)
        rewardedAdManager.loadIfNeeded(); rewardedInterstitialAdManager.loadIfNeeded(); interstitialAdManager.loadIfNeeded()
    }
    func presentRewardedFlow(from viewController: UIViewController,
                             onRewardedAdReward: @escaping () -> Void,
                             onRewardedInterstitialReward: (() -> Void)? = nil,
                             onInterstitialShown: (() -> Void)? = nil,
                             onAllAdsUnavailable: (() -> Void)? = nil,
                             onNextAdConsentRequested: ((Int, @escaping (Bool) -> Void) -> Void)? = nil,
                             onFlowFinished: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        guard !isRunning else { return }
        let owner = UUID()
        guard FullScreenAdGate.shared.reserveFlow(owner) else {
            statusMessage = AdLifecycleError.busy.localizedDescription
            return
        }
        presentationScene = viewController.viewIfLoaded?.window?.windowScene
            ?? UIApplication.shared.activeKeyWindow?.windowScene
        self.owner = owner; isRunning = true; statusMessage = nil; didShowAnyAd = false; wasCancelled = false
        rewardHandlers = [onRewardedAdReward, onRewardedInterstitialReward ?? {}]
        self.onInterstitialShown = onInterstitialShown
        self.onAllAdsUnavailable = onAllAdsUnavailable
        self.onFlowFinished = onFlowFinished
        self.onNextAdConsentRequested = onNextAdConsentRequested
        _ = sequence.start(advance: { [weak self] stage, run, token in
            guard let self = self else { return }
            if stage == 0 {
                self.waitForPresenter(stage: stage, run: run, token: token, deadline: Date().addingTimeInterval(10))
            } else {
                self.pendingConsentToken = token
                guard let consent = self.onNextAdConsentRequested else {
                    self.statusMessage = "다음 광고에 동의하지 않아 남은 광고를 종료했습니다."
                    self.cancel(); return
                }
                consent(stage) { [weak self] accepted in
                    guard let self = self, self.sequence.runID == run, self.pendingConsentToken == token else { return }
                    self.pendingConsentToken = nil
                    if accepted { self.waitForPresenter(stage: stage, run: run, token: token, deadline: Date().addingTimeInterval(10)) }
                    else { self.statusMessage = "남은 광고를 종료했습니다. 이미 얻은 보상은 보존됩니다."; self.cancel() }
                }
            }
        }, finish: { [weak self] in self?.finish() })
    }
    private func waitForPresenter(stage: Int, run: UUID, token: UUID, deadline: Date) {
        // Give SwiftUI confirmation dialogs and SDK dismissal transitions time to finish.
        waitTimer?()
        waitTimer = scheduleAdTask(after: 0.15) { [weak self] in
            guard let self = self, self.sequence.runID == run else { return }
            guard UIApplication.shared.applicationState == .active,
                  self.presentationScene?.activationState == .foregroundActive else {
                self.statusMessage = "앱이 활성화되면 광고를 다시 시도해 주세요."; self.cancel(); return
            }
            if let root = self.presentationScene?.windows.first(where: { $0.isKeyWindow && !$0.isHidden })?.rootViewController,
               root.presentedViewController == nil,
               let presenter = UIApplication.shared.topViewController(base: root),
               presenter.viewIfLoaded?.window != nil,
               presenter.transitionCoordinator == nil,
               !presenter.isBeingPresented, !presenter.isBeingDismissed {
                self.present(stage: stage, run: run, token: token, presenter: presenter)
            } else if Date() < deadline {
                self.waitForPresenter(stage: stage, run: run, token: token, deadline: deadline)
            } else {
                self.statusMessage = "다른 화면이 열려 있어 광고를 표시하지 못했습니다. 화면을 닫고 다시 시도해 주세요."
                self.cancel()
            }
        }
    }
    private func present(stage: Int, run: UUID, token: UUID, presenter: UIViewController) {
        guard let owner = owner, sequence.runID == run else { return }
        let failed: () -> Void = { [weak self] in
            guard let self = self, self.sequence.runID == run else { return }
            self.statusMessage = "일부 광고를 불러오거나 표시하지 못했습니다. 잠시 후 다시 시도해 주세요."
            self.sequence.complete(run: run, token: token)
        }
        let dismissed: () -> Void = { [weak self] in
            guard let self = self, self.sequence.runID == run else { return }
            self.didShowAnyAd = true
            if stage == 2 { self.onInterstitialShown?() }
            self.sequence.complete(run: run, token: token)
        }
        let stalled: (Error) -> Void = { [weak self] error in
            guard let self = self, self.sequence.runID == run else { return }
            AdEventLogger.logError(.flow, event: "present:stalled", error: error)
            self.statusMessage = error.localizedDescription
            self.cancel() // AdSlot still holds the fullscreen gate while SDK UI remains visible.
        }
        // Retain this run's reward closure independently of sequence progression. Reward
        // never advances a step; a late mediation reward is still delivered exactly once.
        let reward = stage < 2 ? rewardHandlers[stage] : {}
        switch stage {
        case 0: rewardedAdManager.presentIfAvailable(from: presenter, owner: owner, onReward: reward,
                                                     onFailure: failed, onDismiss: dismissed, onStall: stalled)
        case 1: rewardedInterstitialAdManager.presentIfAvailable(from: presenter, owner: owner, onReward: reward,
                                                                 onFailure: failed, onDismiss: dismissed, onStall: stalled)
        default: interstitialAdManager.presentIfAvailable(from: presenter, owner: owner,
                                                          onFailure: failed, onDismiss: dismissed, onStall: stalled)
        }
    }
    func cancel() {
        precondition(Thread.isMainThread)
        guard isRunning else { return }
        if statusMessage == nil { statusMessage = "남은 광고를 취소했습니다. 이미 얻은 보상은 보존됩니다." }
        wasCancelled = true
        sequence.cancel()
    }
    private func finish() {
        guard let owner = owner else { return }
        self.owner = nil; waitTimer?(); waitTimer = nil
        pendingConsentToken = nil; onNextAdConsentRequested = nil
        // Invalidate the run before cancelling loads, whose callbacks may be synchronous.
        rewardedAdManager.cancelPending(owner: owner)
        rewardedInterstitialAdManager.cancelPending(owner: owner)
        interstitialAdManager.cancelPending(owner: owner)
        FullScreenAdGate.shared.releaseFlow(owner)
        isRunning = false
        let unavailable = onAllAdsUnavailable, finished = onFlowFinished
        onAllAdsUnavailable = nil; onFlowFinished = nil; onInterstitialShown = nil; rewardHandlers = []
        if !didShowAnyAd, !wasCancelled { unavailable?() }
        finished?()
    }
}
