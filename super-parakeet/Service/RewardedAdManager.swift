//
//  RewardedAdManager.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import Foundation
import GoogleMobileAds
import UIKit

/// 보상형 광고 로드와 표시를 담당하는 매니저.
final class RewardedAdManager: NSObject, ObservableObject {
    /// 현재 광고가 표시 가능한 상태인지 여부.
    @Published private(set) var isAdReady: Bool = false

    private var rewardedAd: GADRewardedAd?
    private var isLoading: Bool = false

    /// 보상형 광고를 미리 로드합니다.
    func loadIfNeeded() {
        guard rewardedAd == nil, isLoading == false else { return }
        load(completion: nil)
    }

    /// 보상형 광고를 로드합니다.
    /// - Parameter completion: 로드 성공 여부 콜백.
    func load(completion: ((Bool) -> Void)?) {
        isLoading = true
        let request = GADRequest()

        GADRewardedAd.load(withAdUnitID: AdMobConfiguration.rewardedAdUnitID,
                           request: request) { [weak self] ad, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isLoading = false

                if let _ = error {
                    self.rewardedAd = nil
                    self.isAdReady = false
                    completion?(false)
                    return
                }

                self.rewardedAd = ad
                self.rewardedAd?.fullScreenContentDelegate = self
                self.isAdReady = true
                completion?(true)
            }
        }
    }

    /// 보상형 광고를 표시합니다. 광고가 준비되지 않았으면 먼저 로드합니다.
    /// - Parameters:
    ///   - viewController: 표시 대상 루트 컨트롤러.
    ///   - onReward: 보상 지급 시 호출되는 콜백.
    ///   - onFailure: 표시 실패 또는 로드 실패 시 호출되는 콜백.
    func presentIfAvailable(from viewController: UIViewController,
                            onReward: @escaping () -> Void,
                            onFailure: (() -> Void)? = nil) {
        if let rewardedAd = rewardedAd {
            rewardedAd.present(fromRootViewController: viewController) {
                onReward()
            }
            return
        }

        load { [weak self] success in
            guard let self = self else { return }
            guard success, let rewardedAd = self.rewardedAd else {
                onFailure?()
                return
            }

            rewardedAd.present(fromRootViewController: viewController) {
                onReward()
            }
        }
    }
}

extension RewardedAdManager: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        DispatchQueue.main.async {
            self.rewardedAd = nil
            self.isAdReady = false
            self.loadIfNeeded()
        }
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        DispatchQueue.main.async {
            self.rewardedAd = nil
            self.isAdReady = false
            self.loadIfNeeded()
        }
    }
}
