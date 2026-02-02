//
//  Extensions.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/19.
//

import Foundation

/// 앱 그룹 설정을 한곳에서 관리합니다.
enum AppGroupConfiguration {
    /// 앱/공유 확장에서 사용하는 App Group 식별자입니다.
    static let identifier = "group.KyoungsueKim.printer"
}

extension UserDefaults {
    /// App Group UserDefaults를 반환합니다. 앱 그룹 접근이 불가하면 `standard`로 폴백합니다.
    static var shared: UserDefaults {
        if let suite = UserDefaults(suiteName: AppGroupConfiguration.identifier) {
            return suite
        }
        assertionFailure("App Group UserDefaults를 열 수 없어 standard로 대체합니다.")
        return .standard
    }
}

extension String {
    /// URL 문자열의 마지막 경로 컴포넌트를 안전하게 복원합니다.
    var decodedLastPathComponent: String {
        let lastPath = (self as NSString).lastPathComponent
        return lastPath.removingPercentEncoding ?? lastPath
    }
}
