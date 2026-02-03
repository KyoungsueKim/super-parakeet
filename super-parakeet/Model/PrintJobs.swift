//
//  PrintJob.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/20.
//

import Combine
import Foundation

/// 프린트 큐 저장소 인터페이스입니다.
protocol PrintJobQueueStoring {
    /// 저장된 프린트 큐 목록을 불러옵니다.
    func loadQueue() -> [String]
    /// 프린트 큐 목록을 저장합니다.
    func saveQueue(_ queue: [String])
    /// 프린트 큐를 모두 삭제합니다.
    func clearQueue()
}

/// 프린트 큐 개별 설정(수량/A3)을 저장하는 인터페이스입니다.
protocol PrintJobSettingsStoring {
    /// 저장된 문서별 설정을 불러옵니다.
    func loadSettings() -> [String: PrintJobSettings]
    /// 문서별 설정을 저장합니다.
    func saveSettings(_ settings: [String: PrintJobSettings])
    /// 문서별 설정을 모두 삭제합니다.
    func clearSettings()
}

/// UserDefaults 기반 프린트 큐 저장소입니다.
final class UserDefaultsPrintJobQueueStore: PrintJobQueueStoring, PrintJobSettingsStoring {
    private let userDefaults: UserDefaults
    private let queueKey = "printQueue"
    private let settingsKey = "printQueueSettings"

    /// App Group UserDefaults를 기본으로 사용합니다.
    init(userDefaults: UserDefaults = .shared) {
        self.userDefaults = userDefaults
    }

    func loadQueue() -> [String] {
        userDefaults.stringArray(forKey: queueKey) ?? []
    }

    func saveQueue(_ queue: [String]) {
        userDefaults.set(queue, forKey: queueKey)
    }

    func clearQueue() {
        userDefaults.removeObject(forKey: queueKey)
    }

    func loadSettings() -> [String: PrintJobSettings] {
        guard let data = userDefaults.data(forKey: settingsKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: PrintJobSettings].self, from: data)) ?? [:]
    }

    func saveSettings(_ settings: [String: PrintJobSettings]) {
        guard let data = try? JSONEncoder().encode(settings) else {
            userDefaults.removeObject(forKey: settingsKey)
            return
        }
        userDefaults.set(data, forKey: settingsKey)
    }

    func clearSettings() {
        userDefaults.removeObject(forKey: settingsKey)
    }
}

/// 프린트 문서별 설정 정보입니다.
struct PrintJobSettings: Codable, Hashable {
    /// 출력 수량.
    var quantity: Int
    /// A3 출력 여부.
    var isA3: Bool

    /// 기본 설정입니다.
    static let `default` = PrintJobSettings(quantity: 1, isA3: false)

    /// 수량이 1 미만인 경우 기본값으로 보정합니다.
    var normalized: PrintJobSettings {
        PrintJobSettings(quantity: max(quantity, 1), isA3: isA3)
    }
}

/// 프린트 큐 항목의 표시/업로드에 필요한 요약 정보입니다.
struct PrintJobDescriptor: Hashable {
    /// 원본 파일 URL 문자열.
    let urlString: String
    /// 출력 수량.
    let quantity: Int
    /// A3 출력 여부.
    let isA3: Bool
}

/// 프린트 큐 상태와 사용자 설정(A3/수량)을 관리합니다.
final class PrintJobQueue: ObservableObject {
    /// 앱 전역에서 사용하는 싱글턴 인스턴스입니다.
    static let shared = PrintJobQueue(store: UserDefaultsPrintJobQueueStore())

    private let store: PrintJobQueueStoring
    private let settingsStore: PrintJobSettingsStoring

    /// 메모리에 유지되는 프린트 큐 목록입니다.
    @Published private(set) var queue: [String] = []

    /// 문서별 출력 설정(A3/수량) 캐시입니다.
    @Published private(set) var jobSettings: [String: PrintJobSettings] = [:]

    /// 저장소 반영 방식입니다.
    private enum PersistAction {
        /// 저장소에 값을 저장합니다.
        case save
        /// 저장소의 값을 제거합니다.
        case clear
        /// 저장소 갱신 없이 메모리만 갱신합니다.
        case none
    }

    /// 저장소를 주입받아 초기화합니다.
    /// - Parameter store: 프린트 큐 저장소.
    init(store: PrintJobQueueStoring & PrintJobSettingsStoring) {
        self.store = store
        self.settingsStore = store
        loadState()
    }

    /// 현재 저장된 프린트 큐 목록을 반환합니다.
    func jobs() -> [String] {
        queue
    }

    /// 큐 변경에 맞춰 내부 상태를 정리하고 UI 갱신을 요청합니다.
    func reload() {
        loadState()
    }

    /// 프린트 큐의 상세 정보를 반환합니다.
    func jobDescriptors() -> [PrintJobDescriptor] {
        jobs().map { urlString in
            let settings = jobSettings[urlString]?.normalized ?? .default
            return PrintJobDescriptor(
                urlString: urlString,
                quantity: settings.quantity,
                isA3: settings.isA3
            )
        }
    }

    /// 지정한 문서의 출력 수량을 반환합니다.
    func jobQuantity(for url: String) -> Int {
        jobSettings[url]?.normalized.quantity ?? 1
    }

    /// 지정한 문서의 출력 수량을 설정합니다.
    func setJobQuantity(_ quantity: Int, for url: String) {
        var updatedSettings = jobSettings
        var settings = updatedSettings[url] ?? .default
        settings.quantity = max(quantity, 1)
        updatedSettings[url] = settings
        updateSettings(updatedSettings)
    }

    /// 지정한 문서의 A3 여부를 반환합니다.
    func isA3(for url: String) -> Bool {
        jobSettings[url]?.isA3 ?? false
    }

    /// 지정한 문서의 A3 여부를 설정합니다.
    func setA3(_ isA3: Bool, for url: String) {
        var updatedSettings = jobSettings
        var settings = updatedSettings[url] ?? .default
        settings.isA3 = isA3
        updatedSettings[url] = settings
        updateSettings(updatedSettings)
    }

    /// 프린트 큐에 문서를 추가합니다.
    func addJob(url: String) {
        if queue.contains(url) {
            var updatedSettings = jobSettings
            let current = updatedSettings[url]?.normalized ?? .default
            updatedSettings[url] = PrintJobSettings(
                quantity: current.quantity + 1,
                isA3: current.isA3
            )
            updateSettings(updatedSettings)
            return
        }

        var updatedQueue = queue
        updatedQueue.append(url)
        updateQueue(updatedQueue)

        var updatedSettings = jobSettings
        updatedSettings[url] = (updatedSettings[url] ?? .default).normalized
        updateSettings(updatedSettings)
    }

    /// 지정한 인덱스의 문서를 삭제합니다.
    func removeJob(at index: Int) {
        guard queue.indices.contains(index) else { return }
        var updatedQueue = queue
        let url = updatedQueue[index]
        updatedQueue.remove(at: index)
        updateQueue(updatedQueue)

        var updatedSettings = jobSettings
        if updatedQueue.contains(url) == false {
            updatedSettings.removeValue(forKey: url)
        }
        updateSettings(updatedSettings)
    }

    /// 다중 선택된 문서를 안전하게 삭제합니다.
    func removeJobs(at offsets: IndexSet) {
        var updatedQueue = queue
        var updatedSettings = jobSettings
        for index in offsets.sorted(by: >) {
            guard updatedQueue.indices.contains(index) else { continue }
            let url = updatedQueue[index]
            updatedQueue.remove(at: index)
            if updatedQueue.contains(url) == false {
                updatedSettings.removeValue(forKey: url)
            }
        }
        updateQueue(updatedQueue)
        updateSettings(updatedSettings)
    }

    /// 프린트 큐를 모두 비웁니다.
    func removeAllJobs() {
        updateQueue([], persist: .clear)
        updateSettings([:], persist: .clear)
    }

    /// 저장소 상태를 메모리에 로드하고 정규화합니다.
    private func loadState() {
        let loadedQueue = store.loadQueue()
        let storedSettings = settingsStore.loadSettings()

        var uniqueQueue: [String] = []
        uniqueQueue.reserveCapacity(loadedQueue.count)

        var occurrenceCounts: [String: Int] = [:]
        occurrenceCounts.reserveCapacity(loadedQueue.count)

        for url in loadedQueue {
            if occurrenceCounts[url] == nil {
                uniqueQueue.append(url)
                occurrenceCounts[url] = 1
            } else {
                occurrenceCounts[url, default: 0] += 1
            }
        }

        var normalized: [String: PrintJobSettings] = [:]
        normalized.reserveCapacity(uniqueQueue.count)
        for url in uniqueQueue {
            let base = (storedSettings[url] ?? .default).normalized
            let multiplier = occurrenceCounts[url] ?? 1
            normalized[url] = PrintJobSettings(
                quantity: base.quantity * max(multiplier, 1),
                isA3: base.isA3
            )
        }

        updateQueue(uniqueQueue, persist: .save)
        updateSettings(normalized, persist: .save)
    }

    /// 큐를 갱신하고 저장소에 반영합니다.
    /// - Parameters:
    ///   - newQueue: 새 프린트 큐 목록.
    ///   - persist: 저장소 반영 방식.
    private func updateQueue(_ newQueue: [String], persist: PersistAction = .save) {
        queue = newQueue
        switch persist {
        case .save:
            store.saveQueue(newQueue)
        case .clear:
            store.clearQueue()
        case .none:
            break
        }
    }

    /// 문서 설정을 갱신하고 저장소에 반영합니다.
    /// - Parameters:
    ///   - newSettings: 새 설정 딕셔너리.
    ///   - persist: 저장소 반영 방식.
    private func updateSettings(_ newSettings: [String: PrintJobSettings], persist: PersistAction = .save) {
        jobSettings = newSettings
        switch persist {
        case .save:
            settingsStore.saveSettings(newSettings)
        case .clear:
            settingsStore.clearSettings()
        case .none:
            break
        }
    }
}
