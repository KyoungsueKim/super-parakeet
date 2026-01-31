//
//  RewardedAdFlowCoordinator.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import Foundation
import UIKit

/// 보상형 광고와 보상형 전면 광고의 순차 노출을 담당하는 코디네이터.
final class RewardedAdFlowCoordinator: ObservableObject {
    private let rewardedAdManager: RewardedAdManager
    private let rewardedInterstitialAdManager: RewardedInterstitialAdManager

    /// 기본 AdMob 매니저를 주입받아 광고 플로우를 구성합니다.
    /// - Parameters:
    ///   - rewardedAdManager: 보상형 광고 매니저.
    ///   - rewardedInterstitialAdManager: 보상형 전면 광고 매니저.
    init(rewardedAdManager: RewardedAdManager = RewardedAdManager(),
         rewardedInterstitialAdManager: RewardedInterstitialAdManager = RewardedInterstitialAdManager()) {
        self.rewardedAdManager = rewardedAdManager
        self.rewardedInterstitialAdManager = rewardedInterstitialAdManager
    }

    /// 광고를 미리 로드합니다.
    func preloadAds() {
        rewardedAdManager.loadIfNeeded()
        rewardedInterstitialAdManager.loadIfNeeded()
    }

    /// 보상형 광고 이후 보상형 전면 광고를 연속으로 표시합니다.
    /// - Parameters:
    ///   - viewController: 광고를 표시할 루트 컨트롤러.
    ///   - onRewardedAdReward: 보상형 광고 보상 지급 시 호출되는 콜백.
    ///   - onRewardedAdFailure: 보상형 광고 로드/표시 실패 시 호출되는 콜백.
    ///   - onRewardedInterstitialReward: 보상형 전면 광고 보상 지급 시 호출되는 콜백.
    ///   - onFlowFinished: 광고 플로우 종료 시 호출되는 콜백.
    func presentRewardedFlow(from viewController: UIViewController,
                             onRewardedAdReward: @escaping () -> Void,
                             onRewardedAdFailure: @escaping () -> Void,
                             onRewardedInterstitialReward: (() -> Void)? = nil,
                             onFlowFinished: @escaping () -> Void) {
        rewardedAdManager.presentIfAvailable(from: viewController,
                                             onReward: onRewardedAdReward,
                                             onFailure: onRewardedAdFailure,
                                             onDismiss: { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    onFlowFinished()
                }
                return
            }

            self.rewardedInterstitialAdManager.presentIfAvailable(from: viewController,
                                                                  onReward: {
                onRewardedInterstitialReward?()
            }, onFailure: {
                DispatchQueue.main.async {
                    onFlowFinished()
                }
            }, onDismiss: {
                DispatchQueue.main.async {
                    onFlowFinished()
                }
            })
        })
    }
}
