//
//  PhoneNumberValidator.swift
//  super-parakeet
//
//  Created by Codex on 2026/02/04.
//

import Foundation

/// 휴대폰 번호 검증을 담당하는 유틸리티입니다.
enum PhoneNumberValidator {
    /// 로그인에 사용하는 휴대폰 번호 규칙을 만족하는지 확인합니다.
    /// - Parameter value: 입력 문자열.
    /// - Returns: 유효한 번호인지 여부.
    static func isValid(_ value: String) -> Bool {
        let pattern = "010[0-9]{8}"
        return value.count == 11 && value.range(of: pattern, options: .regularExpression) != nil
    }
}
