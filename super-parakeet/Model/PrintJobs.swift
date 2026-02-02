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

/// UserDefaults 기반 프린트 큐 저장소입니다.
final class UserDefaultsPrintJobQueueStore: PrintJobQueueStoring {
    private let userDefaults: UserDefaults
    private let queueKey = "printQueue"

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
    private var jobQuantities: [String: Int] = [:]
    private var jobIsA3: [String: Bool] = [:]

    /// 저장소를 주입받아 초기화합니다.
    /// - Parameter store: 프린트 큐 저장소.
    init(store: PrintJobQueueStoring) {
        self.store = store
    }

    /// 현재 저장된 프린트 큐 목록을 반환합니다.
    func jobs() -> [String] {
        store.loadQueue()
    }

    /// 큐 변경에 맞춰 내부 상태를 정리하고 UI 갱신을 요청합니다.
    func reload() {
        let queueSet = Set(jobs())
        jobQuantities = jobQuantities.filter { queueSet.contains($0.key) }
        jobIsA3 = jobIsA3.filter { queueSet.contains($0.key) }
        objectWillChange.send()
    }

    /// 프린트 큐의 상세 정보를 반환합니다.
    func jobDescriptors() -> [PrintJobDescriptor] {
        jobs().map { urlString in
            PrintJobDescriptor(
                urlString: urlString,
                quantity: max(jobQuantities[urlString] ?? 1, 1),
                isA3: jobIsA3[urlString] ?? false
            )
        }
    }

    /// 지정한 문서의 출력 수량을 반환합니다.
    func jobQuantity(for url: String) -> Int {
        jobQuantities[url] ?? 1
    }

    /// 지정한 문서의 출력 수량을 설정합니다.
    func setJobQuantity(_ quantity: Int, for url: String) {
        jobQuantities[url] = max(quantity, 1)
        objectWillChange.send()
    }

    /// 지정한 문서의 A3 여부를 반환합니다.
    func isA3(for url: String) -> Bool {
        jobIsA3[url] ?? false
    }

    /// 지정한 문서의 A3 여부를 설정합니다.
    func setA3(_ isA3: Bool, for url: String) {
        jobIsA3[url] = isA3
        objectWillChange.send()
    }

    /// 프린트 큐에 문서를 추가합니다.
    func addJob(url: String) {
        var queue = jobs()
        queue.append(url)
        store.saveQueue(queue)
        objectWillChange.send()
    }

    /// 지정한 인덱스의 문서를 삭제합니다.
    func removeJob(at index: Int) {
        var queue = jobs()
        guard queue.indices.contains(index) else { return }
        let url = queue[index]
        jobQuantities.removeValue(forKey: url)
        jobIsA3.removeValue(forKey: url)
        queue.remove(at: index)
        store.saveQueue(queue)
        objectWillChange.send()
    }

    /// 다중 선택된 문서를 안전하게 삭제합니다.
    func removeJobs(at offsets: IndexSet) {
        var queue = jobs()
        for index in offsets.sorted(by: >) {
            guard queue.indices.contains(index) else { continue }
            let url = queue[index]
            jobQuantities.removeValue(forKey: url)
            jobIsA3.removeValue(forKey: url)
            queue.remove(at: index)
        }
        store.saveQueue(queue)
        objectWillChange.send()
    }

    /// 프린트 큐를 모두 비웁니다.
    func removeAllJobs() {
        jobQuantities.removeAll()
        jobIsA3.removeAll()
        store.clearQueue()
        objectWillChange.send()
    }
}
