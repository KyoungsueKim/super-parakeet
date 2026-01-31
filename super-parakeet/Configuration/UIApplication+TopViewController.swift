//
//  UIApplication+TopViewController.swift
//  super-parakeet
//
//  Created by Codex on 2026/01/31.
//

import UIKit

/// 현재 표시 중인 최상위 UIViewController를 찾기 위한 유틸리티.
extension UIApplication {
    /// 활성 씬에서 키 윈도우를 반환합니다.
    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// 최상위 UIViewController를 반환합니다.
    /// - Parameter base: 탐색을 시작할 뷰 컨트롤러.
    /// - Returns: 최상위 UIViewController.
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseController = base ?? activeKeyWindow?.rootViewController

        if let navigation = baseController as? UINavigationController {
            return topViewController(base: navigation.visibleViewController)
        }

        if let tabBar = baseController as? UITabBarController,
           let selected = tabBar.selectedViewController {
            return topViewController(base: selected)
        }

        if let presented = baseController?.presentedViewController {
            return topViewController(base: presented)
        }

        return baseController
    }
}
