import UIKit

extension UIApplication {
    /// Use a foreground scene only. Background scene keys may remain marked key.
    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow && !$0.isHidden && $0.alpha > 0 }
    }
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let controller = base ?? activeKeyWindow?.rootViewController
        if let navigation = controller as? UINavigationController {
            return topViewController(base: navigation.visibleViewController)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(base: presented)
        }
        return controller
    }
}
