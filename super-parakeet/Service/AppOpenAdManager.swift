import Foundation
import Combine
import GoogleMobileAds
import UIKit

@MainActor
final class AppOpenAdManager: NSObject, ObservableObject {
    static let shared = AppOpenAdManager()
    private var isAppActive = false
    private var presentingAd: AppOpenAd?
    private var presentationEnd: ((Bool) -> Void)?
    private lazy var slot = AdSlot<AppOpenAd>(expiry: 4 * 3600) { completion in
        AppOpenAd.load(with: AdMobConfiguration.appOpenAdUnitID, request: Request()) { ad, error in
            DispatchQueue.main.async {
                if let ad = ad { completion(.success(ad)) }
                else { completion(.failure(error ?? AdLifecycleError.unavailable)) }
            }
        }
    }
    func updateAppActive(_ isActive: Bool) {
        precondition(Thread.isMainThread)
        isAppActive = isActive
        if !isActive { slot.cancelPending(owner: nil) }
    }
    func updatePreference(isEnabled: Bool, viewController: UIViewController?) {
        precondition(Thread.isMainThread)
        if isEnabled { showAdIfAvailable(from: viewController) }
        else { slot.cancelPending(owner: nil) }
        // Never clear a live SDK ad/delegate when a preference changes.
    }
    func isAdValid() -> Bool { precondition(Thread.isMainThread); return slot.isReady }
    func loadIfNeeded() {
        precondition(Thread.isMainThread)
        guard AppOpenAdPreference.isEnabled else { return }
        slot.load()
    }
    func showAdIfAvailable(from viewController: UIViewController?) {
        precondition(Thread.isMainThread)
        guard AppOpenAdPreference.isEnabled, isAppActive,
              FullScreenAdGate.shared.flow == nil,
              FullScreenAdGate.shared.presentation == nil,
              !slot.isPresenting, !slot.hasPendingPresentation else { return }
        let requestedScene = viewController?.viewIfLoaded?.window?.windowScene
            ?? UIApplication.shared.activeKeyWindow?.windowScene
        var presenter: UIViewController?
        var visibility: AdPresentationVisibility?
        slot.present(owner: nil, canPresent: { [weak self] ad in
            guard self?.isAppActive == true, AppOpenAdPreference.isEnabled,
                  UIApplication.shared.applicationState == .active,
                  requestedScene?.activationState == .foregroundActive,
                  let root = requestedScene?.windows.first(where: { $0.isKeyWindow && !$0.isHidden })?.rootViewController,
                  root.presentedViewController == nil,
                  let current = UIApplication.shared.topViewController(base: root),
                  current.viewIfLoaded?.window != nil,
                  current.transitionCoordinator == nil,
                  !current.isBeingPresented, !current.isBeingDismissed else { throw AdLifecycleError.unavailable }
            try ad.canPresent(from: current); presenter = current; visibility = AdPresentationVisibility(presenter: current)
        }, isVisible: {
            visibility?.isSDKUIVisible() ?? false
        }, show: { [weak self] ad, _, end in
            guard let self = self, let presenter = presenter else { end(false); return }
            self.presentingAd = ad; self.presentationEnd = end
            ad.fullScreenContentDelegate = self
            ad.present(from: presenter)
        }, onStall: { error in
            AdEventLogger.logError(.appOpen, event: "present:timeoutVisible", error: error)
        }, onEnd: { [weak self] _ in
            self?.presentationEnd = nil; self?.presentingAd = nil
            self?.loadIfNeeded()
        })
    }
}

extension AppOpenAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let current = self.presentingAd,
                  (ad as AnyObject) === current else { return }
            AdEventLogger.log(.appOpen, event: "dismiss")
            self.presentationEnd?(true)
        }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let current = self.presentingAd,
                  (ad as AnyObject) === current else { return }
            AdEventLogger.logError(.appOpen, event: "present:failure", error: error)
            self.presentationEnd?(false)
        }
    }
}
