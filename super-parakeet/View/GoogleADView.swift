//
//  GoogleADView.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/09/10.
//

import Foundation
import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

class GoogleAdViewUIController: UIViewController {
    var banner: GADBannerView? = nil
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if banner == nil {
            GADMobileAds.sharedInstance().start(completionHandler: nil)

            // DispatchQueue 이용
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
              ATTrackingManager.requestTrackingAuthorization(completionHandler: { _ in })
            }
        }
        
        loadBanner()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: nil) { [self] context in
            loadBanner()
        }
    }
    
    func loadBanner() {
        let bannerWidth = self.view.frame.size.width
        
        let bannerSize = GADPortraitAnchoredAdaptiveBannerAdSizeWithWidth(bannerWidth)
        
        banner = GADBannerView(adSize: bannerSize)
        
        guard let banner = self.banner else { return }
        
        banner.rootViewController = self
        self.view.addSubview(banner)
        self.view.frame = CGRect(origin: .zero, size: bannerSize.size)
        
        banner.adUnitID = "ca-app-pub-8286712861565957/5082638113"
        
        let request = GADRequest()
        request.scene = self.view.window?.windowScene
        banner.load(request)
        
    }
}

struct GoogleAdView: UIViewControllerRepresentable {
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = GoogleAdViewUIController()

        return viewController
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        
    }
    
    
}
