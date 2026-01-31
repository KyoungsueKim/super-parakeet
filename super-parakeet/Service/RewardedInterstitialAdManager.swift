//
//  RewardedInterstitialAdManager.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import Foundation
import GoogleMobileAds
import UIKit

/// 보상형 전면 광고 로드와 표시를 담당하는 매니저.
final class RewardedInterstitialAdManager: NSObject, ObservableObject {
    /// 현재 광고가 표시 가능한 상태인지 여부.
    @Published private(set) var isAdReady: Bool = false

    private var rewardedInterstitialAd: RewardedInterstitialAd?
    private var isLoading: Bool = false
    private var onDismissHandler: (() -> Void)?
    private var onFailureHandler: (() -> Void)?

    /// 보상형 전면 광고를 미리 로드합니다.
    func loadIfNeeded() {
        guard rewardedInterstitialAd == nil, isLoading == false else { return }
        AdEventLogger.log(.rewardedInterstitial, event: "loadIfNeeded")
        load(completion: nil)
    }

    /// 보상형 전면 광고를 로드합니다.
    /// - Parameter completion: 로드 성공 여부 콜백.
    func load(completion: ((Bool) -> Void)?) {
        AdEventLogger.log(.rewardedInterstitial, event: "load:start")
        isLoading = true
        let request = Request()

        RewardedInterstitialAd.load(with: AdMobConfiguration.rewardedInterstitialAdUnitID,
                                    request: request) { [weak self] ad, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    AdEventLogger.logError(.rewardedInterstitial, event: "load:failure", error: error)
                    self.rewardedInterstitialAd = nil
                    self.isAdReady = false
                    completion?(false)
                    return
                }

                self.rewardedInterstitialAd = ad
                self.rewardedInterstitialAd?.fullScreenContentDelegate = self
                self.isAdReady = true
                AdEventLogger.log(.rewardedInterstitial, event: "load:success")
                completion?(true)
            }
        }
    }

    /// 보상형 전면 광고를 표시합니다. 광고가 준비되지 않았으면 먼저 로드합니다.
    /// - Parameters:
    ///   - viewController: 표시 대상 루트 컨트롤러.
    ///   - onReward: 보상 지급 시 호출되는 콜백.
    ///   - onFailure: 표시 실패 또는 로드 실패 시 호출되는 콜백.
    ///   - onDismiss: 광고가 종료된 직후 호출되는 콜백.
    func presentIfAvailable(from viewController: UIViewController,
                            onReward: @escaping () -> Void,
                            onFailure: (() -> Void)? = nil,
                            onDismiss: (() -> Void)? = nil) {
        if let rewardedInterstitialAd = rewardedInterstitialAd {
            AdEventLogger.log(.rewardedInterstitial, event: "present:ready")
            onDismissHandler = onDismiss
            onFailureHandler = onFailure
            rewardedInterstitialAd.present(from: viewController) {
                AdEventLogger.log(.rewardedInterstitial, event: "reward:earned")
                onReward()
            }
            return
        }

        AdEventLogger.log(.rewardedInterstitial, event: "present:loadAndShow")
        load { [weak self] success in
            guard let self = self else { return }
            guard success, let rewardedInterstitialAd = self.rewardedInterstitialAd else {
                AdEventLogger.log(.rewardedInterstitial, event: "present:loadFailure")
                onFailure?()
                return
            }

            self.onDismissHandler = onDismiss
            self.onFailureHandler = onFailure
            rewardedInterstitialAd.present(from: viewController) {
                AdEventLogger.log(.rewardedInterstitial, event: "reward:earned")
                onReward()
            }
        }
    }
}

extension RewardedInterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        DispatchQueue.main.async {
            AdEventLogger.log(.rewardedInterstitial, event: "dismiss")
            self.rewardedInterstitialAd = nil
            self.isAdReady = false
            let dismissHandler = self.onDismissHandler
            self.onDismissHandler = nil
            self.onFailureHandler = nil
            dismissHandler?()
            self.loadIfNeeded()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        DispatchQueue.main.async {
            AdEventLogger.logError(.rewardedInterstitial, event: "present:failure", error: error)
            self.rewardedInterstitialAd = nil
            self.isAdReady = false
            let failureHandler = self.onFailureHandler
            self.onDismissHandler = nil
            self.onFailureHandler = nil
            failureHandler?()
            self.loadIfNeeded()
        }
    }
}
