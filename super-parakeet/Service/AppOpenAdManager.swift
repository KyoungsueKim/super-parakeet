//
//  AppOpenAdManager.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import Foundation
import GoogleMobileAds
import UIKit

/// 앱 오프닝 광고 로드와 표시를 담당하는 매니저.
final class AppOpenAdManager: NSObject, ObservableObject {
    static let shared = AppOpenAdManager()

    private let adExpiryInterval: TimeInterval = 4 * 60 * 60
    private var appOpenAd: AppOpenAd?
    private var loadTime: Date?
    private var isLoading = false
    private var isShowing = false
    private var shouldShowWhenLoaded = false
    private var isAppActive = false
    private weak var lastRootViewController: UIViewController?

    /// 앱 활성화 상태를 업데이트합니다.
    /// - Parameter isActive: 앱 활성화 여부.
    func updateAppActive(_ isActive: Bool) {
        isAppActive = isActive
    }

    /// 광고 활성화 설정 변경 시 내부 상태를 갱신합니다.
    /// - Parameters:
    ///   - isEnabled: 광고 활성화 여부.
    ///   - viewController: 현재 최상위 뷰 컨트롤러.
    func updatePreference(isEnabled: Bool, viewController: UIViewController?) {
        if isEnabled {
            AdEventLogger.log(.appOpen, event: "preference:enabled")
            showAdIfAvailable(from: viewController)
        } else {
            AdEventLogger.log(.appOpen, event: "preference:disabled")
            resetAdState()
        }
    }

    /// 앱 오프닝 광고를 표시하거나 로드합니다.
    /// - Parameter viewController: 표시 대상 루트 컨트롤러.
    func showAdIfAvailable(from viewController: UIViewController?) {
        guard AppOpenAdPreference.isEnabled else {
            AdEventLogger.log(.appOpen, event: "show:skippedDisabled")
            return
        }

        lastRootViewController = viewController ?? UIApplication.shared.topViewController()
        shouldShowWhenLoaded = true

        if isShowing {
            AdEventLogger.log(.appOpen, event: "show:alreadyShowing")
            return
        }

        if isAdAvailable() {
            presentAd(from: resolveRootViewController())
            return
        }

        AdEventLogger.log(.appOpen, event: "show:loadNeeded")
        loadIfNeeded()
    }

    /// 광고가 유효한지 확인합니다.
    /// - Returns: 유효하면 true.
    func isAdValid() -> Bool {
        isAdAvailable()
    }

    /// 광고를 미리 로드합니다.
    func loadIfNeeded() {
        guard AppOpenAdPreference.isEnabled else {
            AdEventLogger.log(.appOpen, event: "load:skippedDisabled")
            return
        }

        guard isLoading == false else {
            AdEventLogger.log(.appOpen, event: "load:inProgress")
            return
        }

        if isAdAvailable() {
            AdEventLogger.log(.appOpen, event: "load:skippedValid")
            return
        }

        AdEventLogger.log(.appOpen, event: "load:start")
        isLoading = true
        let request = Request()

        AppOpenAd.load(with: AdMobConfiguration.appOpenAdUnitID,
                       request: request) { [weak self] (ad: AppOpenAd?, error: Error?) in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    AdEventLogger.logError(.appOpen, event: "load:failure", error: error)
                    self.appOpenAd = nil
                    self.loadTime = nil
                    return
                }

                self.appOpenAd = ad
                self.appOpenAd?.fullScreenContentDelegate = self
                self.loadTime = Date()
                AdEventLogger.log(.appOpen, event: "load:success")

                if self.shouldShowWhenLoaded, self.isAppActive {
                    self.presentAd(from: self.resolveRootViewController())
                }
            }
        }
    }

    private func presentAd(from viewController: UIViewController?) {
        guard let appOpenAd = appOpenAd else { return }
        guard let viewController = viewController else {
            AdEventLogger.log(.appOpen, event: "present:missingRootViewController")
            retryPresentIfPossible()
            return
        }

        AdEventLogger.log(.appOpen, event: "present:start")
        isShowing = true
        shouldShowWhenLoaded = false
        appOpenAd.present(from: viewController)
    }

    private func resolveRootViewController() -> UIViewController? {
        if let viewController = lastRootViewController {
            return viewController
        }
        return UIApplication.shared.topViewController() ?? UIApplication.shared.activeKeyWindow?.rootViewController
    }

    private func retryPresentIfPossible() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            guard self.shouldShowWhenLoaded, self.isAppActive, self.isAdAvailable() else { return }
            self.presentAd(from: self.resolveRootViewController())
        }
    }

    private func resetAdState() {
        appOpenAd = nil
        loadTime = nil
        isLoading = false
        isShowing = false
        shouldShowWhenLoaded = false
    }

    private func isAdAvailable() -> Bool {
        guard let loadTime = loadTime, appOpenAd != nil else { return false }
        let isValid = Date().timeIntervalSince(loadTime) < adExpiryInterval
        if isValid == false {
            AdEventLogger.log(.appOpen, event: "ad:expired")
            appOpenAd = nil
            self.loadTime = nil
        }
        return isValid
    }
}

extension AppOpenAdManager: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        DispatchQueue.main.async {
            AdEventLogger.log(.appOpen, event: "present:will")
        }
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        DispatchQueue.main.async {
            AdEventLogger.log(.appOpen, event: "impression")
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        DispatchQueue.main.async {
            AdEventLogger.log(.appOpen, event: "dismiss")
            self.appOpenAd = nil
            self.loadTime = nil
            self.isShowing = false
            self.loadIfNeeded()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        DispatchQueue.main.async {
            AdEventLogger.logError(.appOpen, event: "present:failure", error: error)
            self.appOpenAd = nil
            self.loadTime = nil
            self.isShowing = false
            self.loadIfNeeded()
        }
    }
}
