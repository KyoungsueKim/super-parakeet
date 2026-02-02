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
    private var banner: BannerView?
    
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
        let bannerWidth = view.bounds.width
        guard bannerWidth > 0 else { return }

        let bannerSize = portraitAnchoredAdaptiveBanner(width: bannerWidth)

        if let existingBanner = banner, existingBanner.adSize.size == bannerSize.size {
            return
        }

        banner?.removeFromSuperview()
        let newBanner = BannerView(adSize: bannerSize)
        banner = newBanner

        newBanner.rootViewController = self
        view.addSubview(newBanner)
        view.frame = CGRect(origin: .zero, size: bannerSize.size)

        newBanner.adUnitID = AdMobConfiguration.bannerAdUnitID

        let request = Request()
        request.scene = view.window?.windowScene
        newBanner.load(request)
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
