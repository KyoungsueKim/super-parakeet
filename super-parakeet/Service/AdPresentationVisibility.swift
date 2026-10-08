import UIKit

/// Observe only the scene that actually presented this ad. A different scene's key
/// window says nothing about whether the SDK's UI is still on screen here.
@MainActor
final class AdPresentationVisibility {
    private weak var presenter: UIViewController?
    private weak var scene: UIWindowScene?
    private let baselineVisibleWindows: Set<ObjectIdentifier>

    init(presenter: UIViewController) {
        self.presenter = presenter
        let scene = presenter.viewIfLoaded?.window?.windowScene
        self.scene = scene
        baselineVisibleWindows = Set((scene?.windows ?? []).filter(Self.isVisible).map(ObjectIdentifier.init))
    }
    private static func isVisible(_ window: UIWindow) -> Bool {
        !window.isHidden && window.alpha > 0 && window.rootViewController != nil
    }
    func isSDKUIVisible() -> Bool {
        guard let scene = scene else { return false }
        let facts = AdVisibilityFacts(
            originalSceneIsForeground: scene.activationState == .foregroundActive,
            presenterHasModalOrTransition: presenter?.presentedViewController != nil || presenter?.transitionCoordinator != nil,
            originalSceneHasNewVisibleWindow: scene.windows.contains {
                Self.isVisible($0) && !baselineVisibleWindows.contains(ObjectIdentifier($0))
            })
        return facts.shouldWaitForSDKDismissal
    }
}
