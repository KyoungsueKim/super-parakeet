//
//  AppLogger.swift
//  super-parakeet
//
//  Created by Codex on 2026/02/03.
//

import Foundation
import os

/// 앱 전반에서 사용하는 OSLog 로거 모음입니다.
enum AppLogger {
    /// 로깅에 사용하는 subsystem 값입니다.
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.kyoungsuekim.super-parakeet"

    /// 광고 관련 로그를 기록합니다.
    static let ads = Logger(subsystem: subsystem, category: "ads")

    /// 네트워크 관련 로그를 기록합니다.
    static let network = Logger(subsystem: subsystem, category: "network")
}
