//
//  AdMobInitializer.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import AppTrackingTransparency
import Foundation
import GoogleMobileAds

/// AdMob SDK 초기화와 추적 권한 요청을 담당하는 유틸리티.
enum AdMobInitializer {
    /// AdMob SDK를 시작하고 필요 시 추적 권한을 요청합니다.
    static func start() {
        GADMobileAds.sharedInstance().start { status in
            AdMobAdapterStatusLogger.log(status: status)
        }
        requestTrackingAuthorizationIfNeeded()
    }

    private static func requestTrackingAuthorizationIfNeeded() {
        if #available(iOS 14, *) {
            // 앱 진입 직후 시스템 권한 UI가 겹치지 않도록 지연 호출합니다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                ATTrackingManager.requestTrackingAuthorization(completionHandler: { _ in })
            }
        }
    }
}

/// AdMob 미디에이션 어댑터 초기화 상태 로깅 유틸리티.
private enum AdMobAdapterStatusLogger {
    /// 어댑터 상태의 description을 출력합니다.
    /// - Parameter status: AdMob 초기화 상태.
    static func log(status: GADInitializationStatus) {
        let adapterStatuses = status.adapterStatusesByClassName
        if adapterStatuses.isEmpty {
            print("[AdMob] No adapter status available.")
            return
        }

        for (className, adapterStatus) in adapterStatuses {
            print("[AdMob] Adapter: \(className) / Status: \(adapterStatus.state) / Description: \(adapterStatus.description)")
        }
    }
}
