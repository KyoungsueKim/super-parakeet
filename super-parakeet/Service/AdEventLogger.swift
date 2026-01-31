//
//  AdEventLogger.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import Foundation

/// 광고 이벤트 로그 출력 전용 유틸리티.
enum AdEventLogger {
    /// 광고 유형 구분자.
    enum AdType: String {
        case rewarded = "Rewarded"
        case rewardedInterstitial = "RewardedInterstitial"
        case interstitial = "Interstitial"
        case appOpen = "AppOpen"
        case flow = "Flow"
    }

    /// 광고 이벤트를 표준 출력으로 기록합니다.
    /// - Parameters:
    ///   - type: 광고 유형.
    ///   - event: 발생한 이벤트 명.
    ///   - detail: 상세 메시지.
    static func log(_ type: AdType, event: String, detail: String? = nil) {
        if let detail = detail {
            print("[Ad][\(type.rawValue)] \(event) - \(detail)")
            return
        }
        print("[Ad][\(type.rawValue)] \(event)")
    }
}
