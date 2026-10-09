import Foundation
import Combine

// Only UI/SDK boundaries are mocked. The coordinator and AdSlot are production code.
final class UIView { var window: UIWindow? }
final class UIViewController {
    var viewIfLoaded: UIView? = UIView()
    var presentedViewController: UIViewController?
    var transitionCoordinator: AnyObject?
    var isBeingPresented = false, isBeingDismissed = false
}
final class UIWindow {
    var isKeyWindow = true, isHidden = false
    var rootViewController: UIViewController?
    weak var windowScene: UIWindowScene?
}
final class UIWindowScene {
    enum State { case foregroundActive, background }
    var activationState = State.foregroundActive
    var windows: [UIWindow] = []
}
final class UIApplication {
    enum State { case active, background }
    static let shared = UIApplication()
    var applicationState = State.active
    var activeKeyWindow: UIWindow?
    func topViewController(base: UIViewController? = nil) -> UIViewController? { base ?? activeKeyWindow?.rootViewController }
}
enum AdEventLogger {
    enum Kind { case flow }
    static func logError(_ kind: Kind, event: String, error: Error) {}
}
final class MockClock {
    var time: TimeInterval = 0
    struct Work { let id: UUID; let deadline: TimeInterval; let action: () -> Void }
    var work: [Work] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void {
        let id = UUID(); work.append(Work(id: id, deadline: time + delay, action: action))
        return { self.work.removeAll { $0.id == id } }
    }
    func advance(_ seconds: TimeInterval) {
        let until = time + seconds
        while let item = work.filter({ $0.deadline <= until }).min(by: { $0.deadline < $1.deadline }) {
            work.removeAll { $0.id == item.id }; time = item.deadline; item.action()
        }
        time = until
    }
}
final class MockAd {}
@MainActor class MockAdManager {
    enum Load { case ready, noFill, pending }
    var mode = Load.ready, loads = 0, shows = 0, visible = false, closeImmediately = false
    let clock = MockClock()
    var loadReply: ((Result<MockAd, Error>) -> Void)?
    var dismiss: ((Bool) -> Void)?, reward: (() -> Void)?
    lazy var slot = AdSlot<MockAd>(now: { self.clock.time }, schedule: clock.schedule) { reply in
        self.loads += 1; self.loadReply = reply
        switch self.mode { case .ready: reply(.success(MockAd())); case .noFill: reply(.failure(AdLifecycleError.unavailable)); case .pending: break }
    }
    func loadIfNeeded() { slot.load() }
    func presentIfAvailable(from: UIViewController, owner: UUID?, onReward: @escaping () -> Void = {},
                            onFailure: @escaping () -> Void, onDismiss: @escaping () -> Void,
                            onStall: @escaping (Error) -> Void) {
        slot.present(owner: owner, canPresent: { _ in }, isVisible: { self.visible }, show: { _, reward, end in
            self.shows += 1; self.visible = true; self.reward = reward
            self.dismiss = { dismissed in self.visible = false; end(dismissed) }
            if self.closeImmediately { self.dismiss?(true) }
        }, onReward: onReward, onStall: onStall, onEnd: { dismissed in
            if dismissed { onDismiss() } else { onFailure() }
        })
    }
    func cancelPending(owner: UUID?) { slot.cancelPending(owner: owner) }
}
@MainActor final class RewardedAdManager: MockAdManager {}
@MainActor final class RewardedInterstitialAdManager: MockAdManager {}
@MainActor final class InterstitialAdManager: MockAdManager {}
