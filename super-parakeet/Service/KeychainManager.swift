//
//  KeychainManager.swift
//  super-parakeet
//
//  Created by Codex on 2026/02/04.
//

import Foundation
import Security

/// 로그인 정보를 안전하게 저장/조회하는 Keychain 래퍼입니다.
final class KeychainManager {
    /// 싱글톤 인스턴스입니다.
    static let shared = KeychainManager()

    private let service: String
    private let account = "login_phone_number"

    /// 기본 서비스 식별자를 구성합니다.
    init(service: String = Bundle.main.bundleIdentifier ?? "super-parakeet") {
        self.service = service
    }

    /// 휴대폰 번호를 Keychain에 저장합니다.
    /// - Parameter phoneNumber: 저장할 휴대폰 번호 문자열.
    /// - Returns: 저장 성공 여부.
    @discardableResult
    func savePhoneNumber(_ phoneNumber: String) -> Bool {
        guard let data = phoneNumber.data(using: .utf8) else { return false }

        let query: [CFString: Any] = baseQuery()
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        let addQuery = query.merging(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// 저장된 휴대폰 번호를 조회합니다.
    /// - Returns: 저장된 휴대폰 번호 또는 nil.
    func loadPhoneNumber() -> String? {
        var query = baseQuery()
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 저장된 휴대폰 번호를 삭제합니다.
    /// - Returns: 삭제 성공 여부(존재하지 않는 경우도 성공으로 처리).
    @discardableResult
    func deletePhoneNumber() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Keychain 공통 쿼리를 구성합니다.
    private func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
