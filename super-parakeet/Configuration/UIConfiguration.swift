//
//  UIConfiguration.swift
//  FirebaseStarterSwiftUIApp
//
//  Created by Duy Bui on 8/15/20.
//  Copyright © 2020 iOS App Templates. All rights reserved.
//

import SwiftUI
import UIKit

class UIConfiguration {
    /// 폰트가 누락된 경우 시스템 폰트로 폴백합니다.
    private static func font(named name: String, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
    }

    // Fonts
    static let titleFont = font(named: "Arial Rounded MT Bold", size: 28, weight: .bold)
    static let middleFont = font(named: "Avenir-Medium", size: 18, weight: .medium)
    static let subtitleFont = font(named: "Avenir-Medium", size: 16, weight: .medium)
    static let buttonFont = font(named: "Avenir-Heavy", size: 18, weight: .heavy)
    static let listFont = font(named: "Avenir-Medium", size: 19, weight: .medium)
    
    // Color
    static let backgroundColor: UIColor = .white
    static let ajouColor = UIColor(hexString: "#0072CE")
    static let ajouSubColor = UIColor(hexString: "#947550")
    static let subtitleColor = UIColor(hexString: "#464646")
    static let middleColor = UIColor(hexString: "#464646")
    static let buttonColor = UIColor(hexString: "#414665")
    static let buttonBorderColor = UIColor(hexString: "#B0B3C6")
}
