import Foundation

@MainActor final class Fixture {
    let root = UIViewController(), window = UIWindow(), scene = UIWindowScene()
    let first = RewardedAdManager(), second = RewardedInterstitialAdManager(), third = InterstitialAdManager()
    var finished = 0, unavailable = 0, earned = 0
    lazy var coordinator = RewardedAdFlowCoordinator(rewardedAdManager: first, rewardedInterstitialAdManager: second, interstitialAdManager: third)
    init() {
        window.rootViewController = root; window.windowScene = scene; scene.windows = [window]
        root.viewIfLoaded?.window = window; UIApplication.shared.activeKeyWindow = window
        UIApplication.shared.applicationState = .active
    }
    func start() {
        coordinator.presentRewardedFlow(from: root, onRewardedAdReward: { self.earned += 1 },
             onRewardedInterstitialReward: { self.earned += 1 }, onAllAdsUnavailable: { self.unavailable += 1 },
             onFlowFinished: { self.finished += 1 })
    }
    func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.25)) }
    func finishRemaining() { second.dismiss?(true); pump(); third.dismiss?(true); pump() }
    func cleanup() { coordinator.cancel(); [first, second, third].forEach { $0.dismiss?(true) }; pump() }
}
func expect(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
var passed = 0
@MainActor func test(_ name: String, _ body: @MainActor (Fixture) -> Void) {
    let f = Fixture(); body(f); f.cleanup(); passed += 1; print("PASS \(name)")
}
@MainActor func runTests() {
test("three ads automatically continue on individual SDK dismissal") { f in
    f.start(); f.pump(); expect(f.first.shows == 1, "first missing")
    f.first.reward?(); f.first.dismiss?(true); f.pump()
    expect(f.second.shows == 1 && f.coordinator.isRunning, "normal dismissal must automatically present second without consent callback")
    f.second.reward?(); f.finishRemaining()
    expect(f.third.shows == 1 && f.finished == 1 && f.earned == 2, "three-stage completion")
}
test("early individual Close continues but grants no missing reward") { f in
    f.start(); f.pump(); f.first.dismiss?(true); f.pump(); f.finishRemaining()
    expect(f.second.shows == 1 && f.third.shows == 1 && f.earned == 0 && f.finished == 1, "early Close must continue")
}
test("fast synchronous SDK close continues all stages once") { f in
    [f.first, f.second, f.third].forEach { $0.closeImmediately = true }
    f.start(); f.pump(); f.pump(); f.pump()
    expect([f.first.shows, f.second.shows, f.third.shows] == [1,1,1] && f.finished == 1, "fast close lost stage")
}
test("duplicate and stale callbacks cannot skip or repeat next stage") { f in
    f.start(); f.pump(); let old = f.first.dismiss; old?(true); old?(false); f.pump(); old?(true)
    expect(f.second.shows == 1 && f.third.shows == 0, "duplicate advanced wrong stage")
    f.finishRemaining(); expect(f.finished == 1, "duplicate finish")
}
test("load failure and presentation failure continue to remaining stages") { f in
    f.first.mode = .noFill; f.start(); f.pump(); f.pump()
    expect(f.second.shows == 1, "no-fill blocked second")
    f.second.dismiss?(false); f.pump(); f.third.dismiss?(true); f.pump()
    expect(f.third.shows == 1 && f.finished == 1, "presentation failure blocked third")
}
test("all no-fill finishes once with unavailable callback") { f in
    [f.first, f.second, f.third].forEach { $0.mode = .noFill }
    f.start(); f.pump(); f.pump(); f.pump()
    expect(f.finished == 1 && f.unavailable == 1 && !f.coordinator.isRunning, "all no-fill never finished")
}
test("load timeout continues and late response cannot show old ad") { f in
    f.first.mode = .pending; f.start(); f.pump(); f.first.clock.advance(30); f.pump()
    expect(f.second.shows == 1, "timeout blocked second")
    f.first.loadReply?(.success(MockAd())); expect(f.first.shows == 0, "stale load presented")
    f.finishRemaining(); expect(f.finished == 1, "timeout finish missing")
}
test("missing-dismiss timeout advances only after SDK UI is absent") { f in
    f.start(); f.pump(); f.first.visible = false; f.first.clock.advance(180); f.pump()
    expect(f.second.shows == 1, "absent UI did not recover")
    f.finishRemaining(); expect(f.finished == 1, "recovery finish missing")
}
test("missing callback with visible SDK UI never stacks another ad") { f in
    f.start(); f.pump(); f.first.clock.advance(180); f.pump()
    expect(f.second.shows == 0 && f.finished == 0 && f.coordinator.isRunning && f.coordinator.statusMessage == nil && FullScreenAdGate.shared.presentation != nil, "stacked over visible UI")
    f.first.visible = false; f.first.clock.advance(1); f.pump()
    expect(f.second.shows == 1, "UI disappeared but next ad did not resume")
    f.finishRemaining(); expect(f.finished == 1, "recovered flow did not finish")
}
test("long ads still advance on SDK dismissal at every stage") { f in
    f.start(); f.pump()
    for manager in [f.first, f.second, f.third] {
        manager.clock.advance(180); manager.clock.advance(10); f.pump()
        expect(f.coordinator.isRunning && f.finished == 0 && f.coordinator.statusMessage == nil, "watchdog cancelled a valid long ad")
        manager.reward?(); manager.dismiss?(true); f.pump()
    }
    expect([f.first.shows, f.second.shows, f.third.shows] == [1,1,1] && f.finished == 1 && f.earned == 2, "long-ad sequence failed")
}
test("explicit containing-screen exit stops remaining ads without blocking SDK Close") { f in
    f.start(); f.pump(); f.first.reward?(); f.coordinator.cancel(); f.first.dismiss?(true); f.pump()
    expect(f.second.shows == 0 && f.finished == 1 && f.earned == 1 && FullScreenAdGate.shared.presentation == nil, "screen-exit did not stop or blocked Close")
}
test("background exit cancels pending presentation and ignores late load") { f in
    f.first.mode = .pending; f.start(); f.pump(); UIApplication.shared.applicationState = .background
    f.coordinator.cancel(); f.first.loadReply?(.success(MockAd())); f.pump()
    expect(f.first.shows == 0 && f.second.shows == 0 && f.finished == 1, "background late load resumed")
}
print("\(passed) production coordinator regressions passed; UI/SDK mocked, no ads or network")

}
MainActor.assumeIsolated { runTests() }
