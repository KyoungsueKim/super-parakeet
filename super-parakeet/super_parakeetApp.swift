//
//  super_parakeetApp.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/11.
//

import SwiftUI

@main
struct super_parakeetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AdMobInitializer.start()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        AppOpenAdManager.shared.updateAppActive(true)
                        let rootViewController = UIApplication.shared.topViewController()
                        AppOpenAdManager.shared.showAdIfAvailable(from: rootViewController)
                    case .inactive, .background:
                        AppOpenAdManager.shared.updateAppActive(false)
                    @unknown default:
                        break
                    }
                }
        }
    }
}
