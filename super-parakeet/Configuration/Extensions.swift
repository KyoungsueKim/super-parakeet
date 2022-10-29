//
//  Extensions.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/19.
//

import Foundation

extension UserDefaults {
    static var shared: UserDefaults {
        let appGroupId = "group.KyoungsueKim.printer"
        return UserDefaults(suiteName: appGroupId)!
    }
}
