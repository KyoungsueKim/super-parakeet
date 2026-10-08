import Foundation

final class Clock {
    var time: TimeInterval = 0
    struct Task { let id: UUID; let deadline: TimeInterval; let action: () -> Void }
    var tasks: [Task] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void {
        let id = UUID(); tasks.append(Task(id: id, deadline: time + delay, action: action))
        return { [weak self] in self?.tasks.removeAll { $0.id == id } }
    }
    func advance(_ seconds: TimeInterval) {
        let end = time + seconds
        while let task = tasks.filter({ $0.deadline <= end }).min(by: { $0.deadline < $1.deadline }) {
            tasks.removeAll { $0.id == task.id }; time = task.deadline; task.action()
        }
        time = end
    }
}
final class FakeAd {}
final class Fixture {
    let gate = FullScreenAdGate(), clock = Clock()
    var loads: [(Result<FakeAd, Error>) -> Void] = []
    var shows = 0, rewards = 0, ends: [Bool] = [], stalls = 0, visible = false
    var reward: (() -> Void)?, end: ((Bool) -> Void)?
    lazy var slot = AdSlot<FakeAd>(gate: gate, now: { self.clock.time }, schedule: clock.schedule) { self.loads.append($0) }
    func present(owner: UUID? = nil, ready: Bool = true) {
        slot.present(owner: owner, canPresent: { _ in if !ready { throw AdLifecycleError.unavailable } },
                     isVisible: { self.visible }, show: { _, reward, end in
            self.shows += 1; self.reward = reward; self.end = end
        }, onReward: { self.rewards += 1 }, onStall: { _ in self.stalls += 1 }, onEnd: { self.ends.append($0) })
    }
}
var passed = 0
func test(_ name: String, _ body: () -> Void) { body(); passed += 1; print("PASS \(name)") }
func expect(_ condition: @autoclosure () -> Bool, _ message: String = "assertion failed") {
    if !condition() { fatalError(message) }
}
test("preload and present share one load") {
    let f = Fixture(); var callbacks = 0
    f.slot.load { _ in callbacks += 1 }; f.present(); expect(f.loads.count == 1)
    f.loads[0](.success(FakeAd())); expect(f.shows == 1 && callbacks == 1)
}
test("duplicate presentation rejected without overwriting first handlers") {
    let f = Fixture(); f.present(); f.present(); expect(f.loads.count == 1 && f.ends == [false])
    f.loads[0](.success(FakeAd())); f.end?(true); expect(f.ends == [false, true])
}
test("load timeout, retry and stale/duplicate response") {
    let f = Fixture(); f.present(); f.clock.advance(30); expect(f.ends == [false])
    f.present(); expect(f.loads.count == 2)
    f.loads[0](.success(FakeAd())); expect(f.shows == 0)
    f.loads[1](.success(FakeAd())); f.loads[1](.failure(AdLifecycleError.unavailable))
    expect(f.shows == 1); f.end?(true); expect(f.ends == [false, true])
}
test("load failure retry") {
    let f = Fixture(); f.present(); f.loads[0](.failure(AdLifecycleError.unavailable))
    f.present(); f.loads[1](.success(FakeAd())); f.end?(true); expect(f.ends == [false, true])
}
test("cancel pending prevents late presentation but permits cached retry") {
    let f = Fixture(); let owner = UUID(); expect(f.gate.reserveFlow(owner))
    f.present(owner: owner); f.slot.cancelPending(owner: owner); f.loads[0](.success(FakeAd()))
    expect(f.shows == 0 && f.ends == [false]); f.present(owner: owner); expect(f.shows == 1)
}
test("reward never dismisses; reward and terminal callbacks are once-only") {
    let f = Fixture(); f.present(); f.loads[0](.success(FakeAd()))
    f.reward?(); f.reward?(); expect(f.rewards == 1 && f.ends.isEmpty)
    f.end?(true); f.end?(false); expect(f.ends == [true])
}
test("late mediation reward after dismissal is not lost") {
    let f = Fixture(); f.present(); f.loads[0](.success(FakeAd())); f.end?(true)
    f.reward?(); f.reward?(); expect(f.rewards == 1 && f.ends == [true])
}
test("stale dismiss cannot release another presentation") {
    let f = Fixture(); f.present(); f.loads[0](.success(FakeAd())); let oldEnd = f.end
    f.end?(true); f.present(); f.loads[1](.success(FakeAd()))
    oldEnd?(false); expect(f.gate.presentation != nil && f.ends == [true]); f.end?(true)
}
test("ad expires after one hour") {
    let f = Fixture(); f.slot.load(); f.loads[0](.success(FakeAd()))
    f.clock.advance(3601); expect(!f.slot.isReady); f.present(); expect(f.loads.count == 2)
}
test("background or stale presenter fails before SDK presentation") {
    let f = Fixture(); f.present(ready: false); f.loads[0](.success(FakeAd()))
    expect(f.shows == 0 && f.ends == [false] && f.gate.presentation == nil)
}
test("missing dismiss recovers when SDK UI is absent") {
    let f = Fixture(); f.present(); f.loads[0](.success(FakeAd())); f.clock.advance(180)
    expect(f.ends == [false] && f.gate.presentation == nil)
}
test("watchdog and cancel never stack over visible SDK UI") {
    let f = Fixture(); let owner = UUID(); expect(f.gate.reserveFlow(owner))
    f.present(owner: owner); f.loads[0](.success(FakeAd())); f.visible = true
    f.clock.advance(180); expect(f.stalls == 1 && f.ends.isEmpty)
    f.gate.releaseFlow(owner); expect(!f.gate.reserveFlow(UUID()))
    expect(!f.gate.claim(UUID(), owner: nil)); f.clock.advance(10); expect(f.stalls == 1)
    f.visible = false; f.clock.advance(1); expect(f.ends == [false] && f.gate.presentation == nil)
}
test("app-open cannot interrupt sequence including between steps") {
    let gate = FullScreenAdGate(); let owner = UUID(); expect(gate.reserveFlow(owner))
    expect(!gate.claim(UUID(), owner: nil))
    let ad = UUID(); expect(gate.claim(ad, owner: owner)); gate.release(ad)
    expect(!gate.claim(UUID(), owner: nil)); gate.releaseFlow(owner); expect(gate.claim(UUID(), owner: nil))
}
test("three-step order, duplicate failure/dismiss and exactly one finish") {
    let sequence = AdSequence(); var stages: [Int] = [], events: [(UUID, UUID)] = [], finishes = 0
    expect(sequence.start(advance: { stages.append($0); events.append(($1, $2)) }, finish: { finishes += 1 }))
    expect(!sequence.start(advance: { _, _, _ in fatalError() }, finish: {}))
    for i in 0..<3 {
        let (run, token) = events[i]; sequence.complete(run: run, token: token)
        sequence.complete(run: run, token: token)
    }
    expect(stages == [0, 1, 2] && finishes == 1); sequence.cancel(); expect(finishes == 1)
}
test("cancel and retry ignores old callbacks") {
    let sequence = AdSequence(); var events: [(UUID, UUID)] = [], finishes = 0
    func start() { _ = sequence.start(advance: { _, run, token in events.append((run, token)) }, finish: { finishes += 1 }) }
    start(); let old = events[0]; sequence.cancel(); start()
    sequence.complete(run: old.0, token: old.1); expect(sequence.stage == 0 && finishes == 1)
    sequence.cancel(); expect(finishes == 2)
}
test("canPresent failure discards invalid cached ad for retry") {
    let f = Fixture(); f.present(ready: false); f.loads[0](.success(FakeAd()))
    f.present(); expect(f.loads.count == 2); f.loads[1](.success(FakeAd()))
    expect(f.shows == 1)
}
test("failed presentation and missing-dismiss timeout reject late reward") {
    let failed = Fixture(); failed.present(); failed.loads[0](.success(FakeAd()))
    failed.end?(false); failed.reward?(); expect(failed.rewards == 0)
    let timed = Fixture(); timed.present(); timed.loads[0](.success(FakeAd()))
    timed.clock.advance(180); timed.reward?(); expect(timed.rewards == 0)
}
test("different scene key window cannot keep absent SDK UI locked") {
    let facts = AdVisibilityFacts(originalSceneIsForeground: true, presenterHasModalOrTransition: false,
                                  originalSceneHasNewVisibleWindow: false)
    expect(!facts.shouldWaitForSDKDismissal)
    let f = Fixture(); f.present(); f.loads[0](.success(FakeAd()))
    f.visible = facts.shouldWaitForSDKDismissal; f.clock.advance(180)
    expect(f.gate.presentation == nil && f.ends == [false])
}
test("original scene background waits; foreground absent UI recovers") {
    let f = Fixture(); f.present(); f.loads[0](.success(FakeAd()))
    f.visible = AdVisibilityFacts(originalSceneIsForeground: false, presenterHasModalOrTransition: false,
                                 originalSceneHasNewVisibleWindow: false).shouldWaitForSDKDismissal
    f.clock.advance(180); expect(f.gate.presentation != nil && f.ends.isEmpty)
    f.visible = AdVisibilityFacts(originalSceneIsForeground: true, presenterHasModalOrTransition: false,
                                 originalSceneHasNewVisibleWindow: false).shouldWaitForSDKDismissal
    f.clock.advance(1); expect(f.gate.presentation == nil && f.ends == [false])
}
test("SDK modal transition or newly visible original-scene window retains gate") {
    expect(AdVisibilityFacts(originalSceneIsForeground: true, presenterHasModalOrTransition: true,
                            originalSceneHasNewVisibleWindow: false).shouldWaitForSDKDismissal)
    expect(AdVisibilityFacts(originalSceneIsForeground: true, presenterHasModalOrTransition: false,
                            originalSceneHasNewVisibleWindow: true).shouldWaitForSDKDismissal)
}
print("\(passed) regression scenarios passed; no SDK, network or live ads used")
