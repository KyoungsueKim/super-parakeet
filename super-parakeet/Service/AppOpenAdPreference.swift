//
//  AppOpenAdPreference.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import Foundation

/// 앱 오프닝 광고 활성화 여부를 저장/조회하는 유틸리티.
enum AppOpenAdPreference {
    private static let key = "appOpenAdEnabled"

    /// 앱 오프닝 광고 활성화 상태입니다. 기본값은 비활성화입니다.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
