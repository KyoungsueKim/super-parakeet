//
//  PrintJob.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/20.
//

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
    private var jobSettings: [String: PrintJobSettings] = [:]

    /// 저장소를 주입받아 초기화합니다.
    /// - Parameter store: 프린트 큐 저장소.
    init(store: PrintJobQueueStoring & PrintJobSettingsStoring) {
        self.store = store
        self.settingsStore = store
        loadState(notify: false)
    }

    /// 현재 저장된 프린트 큐 목록을 반환합니다.
    func jobs() -> [String] {
        store.loadQueue()
    }

    /// 큐 변경에 맞춰 내부 상태를 정리하고 UI 갱신을 요청합니다.
    func reload() {
        loadState(notify: true)
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
        var settings = jobSettings[url] ?? .default
        settings.quantity = max(quantity, 1)
        jobSettings[url] = settings
        persistSettings()
        objectWillChange.send()
    }

    /// 지정한 문서의 A3 여부를 반환합니다.
    func isA3(for url: String) -> Bool {
        jobSettings[url]?.isA3 ?? false
    }

    /// 지정한 문서의 A3 여부를 설정합니다.
    func setA3(_ isA3: Bool, for url: String) {
        var settings = jobSettings[url] ?? .default
        settings.isA3 = isA3
        jobSettings[url] = settings
        persistSettings()
        objectWillChange.send()
    }

    /// 프린트 큐에 문서를 추가합니다.
    func addJob(url: String) {
        var queue = jobs()
        queue.append(url)
        store.saveQueue(queue)
        if jobSettings[url] == nil {
            jobSettings[url] = .default
            persistSettings()
        }
        objectWillChange.send()
    }

    /// 지정한 인덱스의 문서를 삭제합니다.
    func removeJob(at index: Int) {
        var queue = jobs()
        guard queue.indices.contains(index) else { return }
        let url = queue[index]
        jobSettings.removeValue(forKey: url)
        queue.remove(at: index)
        store.saveQueue(queue)
        persistSettings()
        objectWillChange.send()
    }

    /// 다중 선택된 문서를 안전하게 삭제합니다.
    func removeJobs(at offsets: IndexSet) {
        var queue = jobs()
        for index in offsets.sorted(by: >) {
            guard queue.indices.contains(index) else { continue }
            let url = queue[index]
            jobSettings.removeValue(forKey: url)
            queue.remove(at: index)
        }
        store.saveQueue(queue)
        persistSettings()
        objectWillChange.send()
    }

    /// 프린트 큐를 모두 비웁니다.
    func removeAllJobs() {
        jobSettings.removeAll()
        store.clearQueue()
        settingsStore.clearSettings()
        objectWillChange.send()
    }

    /// 저장소 상태를 메모리에 로드하고 정규화합니다.
    private func loadState(notify: Bool) {
        let queue = store.loadQueue()
        let storedSettings = settingsStore.loadSettings()

        var normalized: [String: PrintJobSettings] = [:]
        for url in queue {
            normalized[url] = (storedSettings[url] ?? .default).normalized
        }

        jobSettings = normalized
        settingsStore.saveSettings(normalized)

        if notify {
            objectWillChange.send()
        }
    }

    /// 현재 설정을 저장소에 반영합니다.
    private func persistSettings() {
        settingsStore.saveSettings(jobSettings)
    }
}
