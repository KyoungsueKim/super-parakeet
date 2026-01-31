//
//  RewardedAdFlowCoordinator.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import Foundation
import UIKit

/// 보상형 광고, 보상형 전면 광고, 전면 광고의 순차 노출을 담당하는 코디네이터.
final class RewardedAdFlowCoordinator: ObservableObject {
    private let rewardedAdManager: RewardedAdManager
    private let rewardedInterstitialAdManager: RewardedInterstitialAdManager
    private let interstitialAdManager: InterstitialAdManager

    /// 기본 AdMob 매니저를 주입받아 광고 플로우를 구성합니다.
    /// - Parameters:
    ///   - rewardedAdManager: 보상형 광고 매니저.
    ///   - rewardedInterstitialAdManager: 보상형 전면 광고 매니저.
    ///   - interstitialAdManager: 전면 광고 매니저.
    init(rewardedAdManager: RewardedAdManager = RewardedAdManager(),
         rewardedInterstitialAdManager: RewardedInterstitialAdManager = RewardedInterstitialAdManager(),
         interstitialAdManager: InterstitialAdManager = InterstitialAdManager()) {
        self.rewardedAdManager = rewardedAdManager
        self.rewardedInterstitialAdManager = rewardedInterstitialAdManager
        self.interstitialAdManager = interstitialAdManager
    }

    /// 광고를 미리 로드합니다.
    func preloadAds() {
        AdEventLogger.log(.flow, event: "preload:start")
        rewardedAdManager.loadIfNeeded()
        rewardedInterstitialAdManager.loadIfNeeded()
        interstitialAdManager.loadIfNeeded()
    }

    /// 보상형 광고 이후 보상형 전면 광고, 전면 광고를 연속으로 표시합니다.
    /// - Parameters:
    ///   - viewController: 광고를 표시할 루트 컨트롤러.
    ///   - onRewardedAdReward: 보상형 광고 보상 지급 시 호출되는 콜백.
    ///   - onRewardedInterstitialReward: 보상형 전면 광고 보상 지급 시 호출되는 콜백.
    ///   - onInterstitialShown: 전면 광고 표시 및 종료 시 호출되는 콜백.
    ///   - onAllAdsUnavailable: 모든 광고가 로드/표시되지 못했을 때 호출되는 콜백.
    ///   - onFlowFinished: 광고 플로우 종료 시 호출되는 콜백.
    func presentRewardedFlow(from viewController: UIViewController,
                             onRewardedAdReward: @escaping () -> Void,
                             onRewardedInterstitialReward: (() -> Void)? = nil,
                             onInterstitialShown: (() -> Void)? = nil,
                             onAllAdsUnavailable: (() -> Void)? = nil,
                             onFlowFinished: @escaping () -> Void) {
        AdEventLogger.log(.flow, event: "start")
        var didShowAnyAd = false

        func finishFlow() {
            if didShowAnyAd == false {
                AdEventLogger.log(.flow, event: "finish:allUnavailable")
                onAllAdsUnavailable?()
            }
            AdEventLogger.log(.flow, event: "finish")
            onFlowFinished()
        }

        func presentInterstitial() {
            interstitialAdManager.presentIfAvailable(from: viewController,
                                                     onFailure: {
                AdEventLogger.log(.flow, event: "interstitial:failure")
                DispatchQueue.main.async {
                    finishFlow()
                }
            }, onDismiss: {
                AdEventLogger.log(.flow, event: "interstitial:dismiss")
                didShowAnyAd = true
                onInterstitialShown?()
                DispatchQueue.main.async {
                    finishFlow()
                }
            })
        }

        func presentRewardedInterstitial() {
            rewardedInterstitialAdManager.presentIfAvailable(from: viewController,
                                                             onReward: {
                AdEventLogger.log(.flow, event: "rewardedInterstitial:reward")
                onRewardedInterstitialReward?()
            }, onFailure: {
                AdEventLogger.log(.flow, event: "rewardedInterstitial:failure")
                DispatchQueue.main.async {
                    presentInterstitial()
                }
            }, onDismiss: {
                AdEventLogger.log(.flow, event: "rewardedInterstitial:dismiss")
                didShowAnyAd = true
                DispatchQueue.main.async {
                    presentInterstitial()
                }
            })
        }

        rewardedAdManager.presentIfAvailable(from: viewController,
                                             onReward: onRewardedAdReward,
                                             onFailure: {
            AdEventLogger.log(.flow, event: "rewarded:failure")
            DispatchQueue.main.async {
                presentRewardedInterstitial()
            }
        }, onDismiss: {
            AdEventLogger.log(.flow, event: "rewarded:dismiss")
            didShowAnyAd = true
            DispatchQueue.main.async {
                presentRewardedInterstitial()
            }
        })
    }
}
