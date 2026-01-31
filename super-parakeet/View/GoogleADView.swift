//
//  GoogleADView.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/09/10.
//

import Foundation
import SwiftUI
import GoogleMobileAds

/// AdMob 배너 광고 전용 컨트롤러.
final class BannerAdViewController: UIViewController {
    var banner: BannerView? = nil
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
        
        let bannerSize = portraitAnchoredAdaptiveBanner(width: bannerWidth)
        
        banner = BannerView(adSize: bannerSize)
        
        guard let banner = self.banner else { return }
        
        banner.rootViewController = self
        self.view.addSubview(banner)
        self.view.frame = CGRect(origin: .zero, size: bannerSize.size)
        
        banner.adUnitID = AdMobConfiguration.bannerAdUnitID
        
        let request = Request()
        request.scene = self.view.window?.windowScene
        banner.load(request)
        
    }
}

/// SwiftUI에서 사용하는 AdMob 배너 광고 뷰.
struct BannerAdView: UIViewControllerRepresentable {
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = BannerAdViewController()

        return viewController
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        
    }
    
    
}
