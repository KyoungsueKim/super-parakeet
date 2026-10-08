import Foundation
import Combine
import GoogleMobileAds
import UIKit

/// Main-thread SDK adapter. AdSlot owns concurrency, expiry, timeout and completion rules.
@MainActor
final class RewardedInterstitialAdManager: NSObject, ObservableObject {
    @Published private(set) var isAdReady = false
    private var presentingAd: RewardedInterstitialAd?
    private var presentationEnd: ((Bool) -> Void)?
    private lazy var slot = AdSlot<RewardedInterstitialAd> { completion in
        RewardedInterstitialAd.load(with: AdMobConfiguration.rewardedInterstitialAdUnitID, request: Request()) { ad, error in
            DispatchQueue.main.async {
                if let ad = ad { completion(.success(ad)) }
                else { completion(.failure(error ?? AdLifecycleError.unavailable)) }
            }
        }
    }
    func loadIfNeeded() { load(completion: nil) }
    func load(completion: ((Bool) -> Void)?) {
        precondition(Thread.isMainThread)
        slot.load { [weak self] ready in self?.isAdReady = ready; completion?(ready) }
    }
    func presentIfAvailable(from viewController: UIViewController, owner: UUID? = nil,
                            onReward: @escaping () -> Void, onFailure: (() -> Void)? = nil,
                            onDismiss: (() -> Void)? = nil,
                            onStall: @escaping (Error) -> Void = { _ in }) {
        precondition(Thread.isMainThread)
        guard !slot.isPresenting, !slot.hasPendingPresentation else { onFailure?(); return }
        let requestedScene = viewController.viewIfLoaded?.window?.windowScene
        var presenter: UIViewController?
        var visibility: AdPresentationVisibility?
        slot.present(owner: owner, canPresent: { ad in
            // Resolve again after asynchronous loading; never retain a dismissed alert/ad as presenter.
            guard UIApplication.shared.applicationState == .active,
                  requestedScene?.activationState == .foregroundActive,
                  let root = requestedScene?.windows.first(where: { $0.isKeyWindow && !$0.isHidden })?.rootViewController,
                  root.presentedViewController == nil,
                  let current = UIApplication.shared.topViewController(base: root),
                  current.viewIfLoaded?.window != nil,
                  !current.isBeingDismissed, !current.isBeingPresented,
                  current.transitionCoordinator == nil else { throw AdLifecycleError.unavailable }
            try ad.canPresent(from: current)
            presenter = current; visibility = AdPresentationVisibility(presenter: current)
        }, isVisible: {
            visibility?.isSDKUIVisible() ?? false
        }, show: { [weak self] ad, reward, end in
            guard let self = self, let presenter = presenter else { end(false); return }
            self.isAdReady = false; self.presentingAd = ad; self.presentationEnd = end
            ad.fullScreenContentDelegate = self
            AdEventLogger.log(.rewardedInterstitial, event: "present:start")
            ad.present(from: presenter, userDidEarnRewardHandler: { DispatchQueue.main.async { reward() } })
        }, onReward: onReward, onStall: onStall, onEnd: { [weak self] dismissed in
            // Duplicate/stale SDK callbacks cannot consume the next ad's handlers.
            self?.presentationEnd = nil; self?.presentingAd = nil
            self?.isAdReady = self?.slot.isReady ?? false
            if dismissed { onDismiss?() } else {
                if let error = self?.slot.lastError { AdEventLogger.logError(.rewardedInterstitial, event: "present:unavailable", error: error) }
                onFailure?()
            }
        })
    }
    func cancelPending(owner: UUID?) { precondition(Thread.isMainThread); slot.cancelPending(owner: owner) }
}

extension RewardedInterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let current = self.presentingAd,
                  (ad as AnyObject) === current else { return }
            AdEventLogger.log(.rewardedInterstitial, event: "dismiss")
            self.presentationEnd?(true)
            self.loadIfNeeded()
        }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let current = self.presentingAd,
                  (ad as AnyObject) === current else { return }
            AdEventLogger.logError(.rewardedInterstitial, event: "present:failure", error: error)
            self.presentationEnd?(false)
            self.loadIfNeeded()
        }
    }
}
