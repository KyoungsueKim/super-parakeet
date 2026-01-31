//
//  AppDelegate.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import UIKit

/// 앱 생명주기를 수신해 앱 오프닝 광고 표시 타이밍을 제어합니다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if AppOpenAdPreference.isEnabled {
            AppOpenAdManager.shared.loadIfNeeded()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppOpenAdManager.shared.updateAppActive(true)
        let rootViewController = UIApplication.shared.topViewController()
        AppOpenAdManager.shared.showAdIfAvailable(from: rootViewController)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        AppOpenAdManager.shared.updateAppActive(false)
    }

    /// 앱 오프닝 광고의 유효성을 확인합니다.
    /// - Returns: 유효하면 true.
    func isAppOpenAdValid() -> Bool {
        AppOpenAdManager.shared.isAdValid()
    }
}
