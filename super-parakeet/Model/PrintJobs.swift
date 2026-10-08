import Combine
import Foundation
import PDFKit
import Darwin

/// 프린트 서버가 지원하는 문서별 단면/양면 출력 모드입니다.
enum PrintDuplexMode: String, Codable, Hashable {
    /// 한 면에만 출력합니다.
    case simplex = "simplex"
    /// 용지의 긴 변을 기준으로 양면 출력합니다.
    case longEdge = "long_edge"

    /// 서버 API에 전달하는 폼 파라미터 값입니다.
    var apiValue: String {
        rawValue
    }

    /// 문서 행 옵션 버튼에 표시할 짧은 제목입니다.
    var displayTitle: String {
        switch self {
        case .simplex:
            return "단면"
        case .longEdge:
            return "양면"
        }
    }

    /// 두 상태 UI에서 다음에 선택할 출력 모드입니다.
    var toggled: PrintDuplexMode {
        switch self {
        case .simplex:
            return .longEdge
        case .longEdge:
            return .simplex
        }
    }
}

/// 프린트 문서별 설정 정보입니다.
struct PrintJobSettings: Codable, Hashable {
    /// 출력 수량.
    var quantity: Int
    /// A3 출력 여부.
    var isA3: Bool
    /// 단면/양면 출력 모드.
    var duplexMode: PrintDuplexMode

    /// 기본 설정입니다.
    static let `default` = PrintJobSettings(quantity: 1, isA3: false, duplexMode: .simplex)

    /// 문서별 출력 설정을 생성합니다.
    /// - Parameters:
    ///   - quantity: 출력 수량.
    ///   - isA3: A3 출력 여부.
    ///   - duplexMode: 단면/양면 출력 모드.
    init(quantity: Int, isA3: Bool, duplexMode: PrintDuplexMode = .simplex) {
        self.quantity = quantity
        self.isA3 = isA3
        self.duplexMode = duplexMode
    }

    /// 저장 데이터의 키 목록입니다.
    private enum CodingKeys: String, CodingKey {
        case quantity
        case isA3
        case duplexMode
    }

    /// 저장된 문서별 출력 설정을 복원합니다.
    /// - Parameter decoder: 저장 데이터 디코더.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? Self.default.quantity
        isA3 = try container.decodeIfPresent(Bool.self, forKey: .isA3) ?? Self.default.isA3
        duplexMode = try container.decodeIfPresent(PrintDuplexMode.self, forKey: .duplexMode) ?? Self.default.duplexMode
    }

    /// 문서별 출력 설정을 저장 가능한 데이터로 변환합니다.
    /// - Parameter encoder: 저장 데이터 인코더.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(isA3, forKey: .isA3)
        try container.encode(duplexMode, forKey: .duplexMode)
    }

    /// 수량이 1 미만인 경우 기본값으로 보정합니다.
    var normalized: PrintJobSettings {
        PrintJobSettings(quantity: max(quantity, 1), isA3: isA3, duplexMode: duplexMode)
    }
}


/// UUID identity is independent of both the display name and the file location.
struct StoredPrintJob: Codable, Hashable {
    let id: UUID
    let urlString: String
    let displayName: String
    var settings: PrintJobSettings
}

struct PrintJobDescriptor: Hashable {
    let id: UUID
    let urlString: String
    let quantity: Int
    let isA3: Bool
    let duplexMode: PrintDuplexMode
}

struct PrintQueueManifest: Codable {
    var version = 1
    var jobs: [StoredPrintJob] = []
}

protocol PrintJobStoring {
    func read() throws -> [StoredPrintJob]
    func transaction(_ change: (inout [StoredPrintJob]) throws -> Void) throws -> [StoredPrintJob]
    func garbageCollect() throws
}

enum PrintQueueError: LocalizedError {
    case containerUnavailable, invalidManifest, invalidPDF, cancelled
    var errorDescription: String? {
        switch self {
        case .containerUnavailable: return "공유 저장소에 접근할 수 없습니다. 앱을 다시 실행해 주세요."
        case .invalidManifest: return "문서 목록을 읽을 수 없습니다. 기존 데이터는 변경하지 않았습니다."
        case .invalidPDF: return "읽을 수 있는 PDF 문서가 아닙니다."
        case .cancelled: return "가져오기를 취소했습니다. 이미 추가된 문서는 보존됩니다."
        }
    }
}

/// Cancellation is serialized with publication, so no commit starts after cancel returns.
final class PDFImportCancellation {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func whileActive<T>(_ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw PrintQueueError.cancelled }
        return try operation()
    }
}

/// One flock-protected, atomically replaced manifest is authoritative in both processes.
/// No operation writes an in-memory snapshot back to disk.
final class SharedPrintJobStore: PrintJobStoring {
    static let shared = SharedPrintJobStore()
    private static let processLock = NSLock()
    private let root: URL?
    private let legacyDefaults: UserDefaults?
    private let fm = FileManager.default

    init(root: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConfiguration.identifier),
         legacyDefaults: UserDefaults? = UserDefaults(suiteName: AppGroupConfiguration.identifier)) {
        self.root = root?.appendingPathComponent("PrintQueue-v1", isDirectory: true)
        self.legacyDefaults = legacyDefaults
    }

    private func locked<T>(_ body: (URL) throws -> T) throws -> T {
        guard let root = root else { throw PrintQueueError.containerUnavailable }
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = open(root.appendingPathComponent("queue.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        defer { flock(fd, LOCK_UN) }
        return try body(root)
    }

    private func load(at root: URL) throws -> PrintQueueManifest {
        let url = root.appendingPathComponent("manifest.json")
        if fm.fileExists(atPath: url.path) {
            let manifest: PrintQueueManifest
            do { manifest = try JSONDecoder().decode(PrintQueueManifest.self, from: Data(contentsOf: url)) }
            catch { throw PrintQueueError.invalidManifest }
            guard manifest.version == 1,
                  Set(manifest.jobs.map { $0.id }).count == manifest.jobs.count,
                  Set(manifest.jobs.map { $0.urlString }).count == manifest.jobs.count else {
                throw PrintQueueError.invalidManifest
            }
            return manifest
        }
        // Migrate once, under the same lock. Retain legacy preferences/files as a backup.
        // Even an empty manifest is persisted; cleared legacy jobs will never be resurrected.
        let urls = legacyDefaults?.stringArray(forKey: "printQueue") ?? []
        var settings: [String: PrintJobSettings] = [:]
        if let data = legacyDefaults?.data(forKey: "printQueueSettings") {
            settings = (try? JSONDecoder().decode([String: PrintJobSettings].self, from: data)) ?? [:]
        }
        var manifest = PrintQueueManifest()
        for url in urls {
            if let index = manifest.jobs.firstIndex(where: { $0.urlString == url }) {
                manifest.jobs[index].settings.quantity += (settings[url] ?? .default).normalized.quantity
            } else {
                manifest.jobs.append(StoredPrintJob(id: UUID(), urlString: url,
                    displayName: URL(string: url)?.lastPathComponent ?? url.decodedLastPathComponent,
                    settings: (settings[url] ?? .default).normalized))
            }
        }
        try save(manifest, at: root)
        return manifest
    }

    private func save(_ manifest: PrintQueueManifest, at root: URL) throws {
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
    }

    func read() throws -> [StoredPrintJob] { try locked { try load(at: $0).jobs } }

    @discardableResult
    func transaction(_ change: (inout [StoredPrintJob]) throws -> Void) throws -> [StoredPrintJob] {
        try locked { root in
            var manifest = try load(at: root)
            try change(&manifest.jobs)
            try save(manifest, at: root)
            return manifest.jobs
        }
    }

    /// Called only by the containing app when no upload session is active. Never
    /// touch legacy documents or staging files that an extension may still be copying.
    func garbageCollect() throws {
        try locked { root in
            let referenced = Set(try load(at: root).jobs.map { $0.id.uuidString })
            let documents = root.appendingPathComponent("documents", isDirectory: true)
            guard fm.fileExists(atPath: documents.path) else { return }
            for folder in try fm.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.isDirectoryKey]) {
                guard UUID(uuidString: folder.lastPathComponent) != nil,
                      !referenced.contains(folder.lastPathComponent),
                      try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                try fm.removeItem(at: folder)
            }
        }
    }

    /// The provider-owned URL is accessed ONLY during its callback. Publication occurs
    /// after a coordinated copy and PDF validation, before the caller reports success.
    func importPDF(from source: URL, name: String?, id: UUID = UUID(),
                   cancellation: PDFImportCancellation = PDFImportCancellation()) throws -> StoredPrintJob {
        try stageAndPublish(name: name ?? source.lastPathComponent, id: id, cancellation: cancellation) { staging in
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { coordinated in
                do { try self.fm.copyItem(at: coordinated, to: staging) } catch { copyError = error }
            }
            if let error = coordinationError { throw error }
            if let error = copyError { throw error }
        }
    }

    func importPDF(data: Data, name: String?, id: UUID = UUID(),
                   cancellation: PDFImportCancellation = PDFImportCancellation()) throws -> StoredPrintJob {
        try stageAndPublish(name: name ?? "Document.pdf", id: id, cancellation: cancellation) {
            try data.write(to: $0, options: .atomic)
        }
    }

    private func stageAndPublish(name: String, id: UUID, cancellation: PDFImportCancellation,
                                 copy: (URL) throws -> Void) throws -> StoredPrintJob {
        guard let root = root else { throw PrintQueueError.containerUnavailable }
        try cancellation.whileActive { }
        // Unique staging paths allow multiple attachments/processes to copy concurrently.
        let stagingDirectory = root.appendingPathComponent("staging", isDirectory: true)
        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let staging = stagingDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? fm.removeItem(at: staging) }
        try copy(staging)
        guard let pdf = PDFDocument(url: staging), pdf.pageCount > 0, !pdf.isLocked else { throw PrintQueueError.invalidPDF }
        var safeName = (name as NSString).lastPathComponent
        if safeName.isEmpty || safeName == "." || safeName == ".." { safeName = "Document.pdf" }
        // Keep filesystem component lengths bounded, and always upload a .pdf filename.
        safeName = String(safeName.prefix(80))
        if !(safeName as NSString).pathExtension.lowercased().elementsEqual("pdf") { safeName += ".pdf" }
        return try cancellation.whileActive {
            try locked { root in
                var manifest = try load(at: root)
                if let existing = manifest.jobs.first(where: { $0.id == id }) { return existing }
                let folder = root.appendingPathComponent("documents", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
                // A previous interrupted publication may leave this UUID's unreferenced directory.
                if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(safeName)
                do {
                    try fm.moveItem(at: staging, to: destination)
                    let job = StoredPrintJob(id: id, urlString: destination.absoluteString, displayName: name, settings: .default)
                    manifest.jobs.append(job)
                    try save(manifest, at: root)
                    return job
                } catch {
                    try? fm.removeItem(at: folder)
                    throw error
                }
            }
        }
    }
}

/// Main-thread UI cache. Every mutation runs against the current locked disk state.
final class PrintJobQueue: ObservableObject {
    static let shared = PrintJobQueue(store: SharedPrintJobStore.shared)
    private let store: PrintJobStoring
    private static var uploadInProgress = false
    @Published private(set) var queue: [String] = []
    @Published private(set) var jobSettings: [String: PrintJobSettings] = [:]
    @Published private(set) var errorMessage: String?
    private var records: [StoredPrintJob] = []

    init(store: PrintJobStoring) { self.store = store; reload(); collectOwnedFiles() }
    /// Both these methods and UI mutations are called on the main actor.
    func beginUpload() -> Bool {
        guard !Self.uploadInProgress else { return false }
        Self.uploadInProgress = true
        return true
    }
    func endUpload() { Self.uploadInProgress = false; collectOwnedFiles() }
    private func collectOwnedFiles() {
        guard !Self.uploadInProgress else { return }
        do { try store.garbageCollect() }
        catch { errorMessage = error.localizedDescription }
    }
    func jobs() -> [String] { queue }
    func displayName(for url: String) -> String { records.first { $0.urlString == url }?.displayName ?? url.decodedLastPathComponent }
    func reload() {
        do { apply(try store.read()); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    private func apply(_ jobs: [StoredPrintJob]) {
        records = jobs; queue = jobs.map { $0.urlString }
        jobSettings = Dictionary(uniqueKeysWithValues: jobs.map { ($0.urlString, $0.settings.normalized) })
    }
    private func mutate(_ change: (inout [StoredPrintJob]) throws -> Void) {
        do { apply(try store.transaction(change)); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    func jobDescriptors() -> [PrintJobDescriptor] {
        records.map { PrintJobDescriptor(id: $0.id, urlString: $0.urlString, quantity: $0.settings.normalized.quantity,
                                        isA3: $0.settings.isA3, duplexMode: $0.settings.duplexMode) }
    }
    func jobQuantity(for url: String) -> Int { jobSettings[url]?.normalized.quantity ?? 1 }
    func isA3(for url: String) -> Bool { jobSettings[url]?.isA3 ?? false }
    func duplexMode(for url: String) -> PrintDuplexMode { jobSettings[url]?.duplexMode ?? .simplex }
    private func updateSetting(for url: String, _ change: (inout PrintJobSettings) -> Void) {
        mutate { jobs in
            guard let index = jobs.firstIndex(where: { $0.urlString == url }) else { return }
            change(&jobs[index].settings)
        }
    }
    func setJobQuantity(_ quantity: Int, for url: String) { updateSetting(for: url) { $0.quantity = max(quantity, 1) } }
    func setA3(_ isA3: Bool, for url: String) { updateSetting(for: url) { $0.isA3 = isA3 } }
    func setDuplexMode(_ mode: PrintDuplexMode, for url: String) { updateSetting(for: url) { $0.duplexMode = mode } }
    func removeJob(at index: Int) { removeJobs(at: IndexSet(integer: index)) }
    func removeJobs(at offsets: IndexSet) {
        let ids = Set(offsets.compactMap { records.indices.contains($0) ? records[$0].id : nil })
        mutate { $0.removeAll { ids.contains($0.id) } }
        collectOwnedFiles()
    }
    func removeAllJobs() {
        // Remove only the snapshot the user saw, preserving concurrent imports.
        let ids = Set(records.map { $0.id })
        mutate { $0.removeAll { ids.contains($0.id) } }
        collectOwnedFiles()
    }
    /// Acknowledge only confirmed uploads, one copy at a time, including partial success.
    func acknowledgeUpload(id: UUID, count: Int) throws {
        guard count > 0 else { return }
        do {
            apply(try store.transaction { jobs in
                guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
                jobs[index].settings.quantity -= count
                if jobs[index].settings.quantity <= 0 { jobs.remove(at: index) }
            })
            errorMessage = nil
            collectOwnedFiles()
        } catch { errorMessage = error.localizedDescription; throw error }
    }
}

/// File and Data representations share the same synchronous commit path.
final class ProviderPDFImporter {
    let store: SharedPrintJobStore
    init(store: SharedPrintJobStore = .shared) { self.store = store }

    @discardableResult
    func load(_ provider: NSItemProvider, id: UUID, cancellation: PDFImportCancellation,
              completion: @escaping (Result<StoredPrintJob, Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 2)
        let name = provider.suggestedName
        func loadData() {
            do { try cancellation.whileActive { } }
            catch { completion(.failure(error)); return }
            let child = provider.loadDataRepresentation(forTypeIdentifier: "com.adobe.pdf") { data, error in
                guard let data = data else { completion(.failure(error ?? PrintQueueError.invalidPDF)); return }
                completion(Result { try self.store.importPDF(data: data, name: name, id: id, cancellation: cancellation) })
            }
            progress.addChild(child, withPendingUnitCount: 1)
        }
        if provider.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
            let child = provider.loadFileRepresentation(forTypeIdentifier: "com.adobe.pdf") { url, _ in
                if let url = url {
                    // The temporary URL must be copied before this callback returns.
                    do {
                        completion(.success(try self.store.importPDF(from: url, name: name, id: id, cancellation: cancellation)))
                    } catch PrintQueueError.cancelled { completion(.failure(PrintQueueError.cancelled)) }
                    catch { loadData() }
                } else { loadData() }
            }
            progress.addChild(child, withPendingUnitCount: 1)
        } else if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            let child = provider.loadObject(ofClass: NSURL.self) { item, error in
                guard let url = item as? URL else { completion(.failure(error ?? PrintQueueError.invalidPDF)); return }
                completion(Result { try self.store.importPDF(from: url, name: name, id: id, cancellation: cancellation) })
            }
            progress.addChild(child, withPendingUnitCount: 1)
        } else { completion(.failure(PrintQueueError.invalidPDF)) }
        return progress
    }
}

/// All UI state is confined to the main queue. Failed attachments retain their UUID
/// on retry; successful attachments are never imported twice.
final class ShareImportSession: ObservableObject {
    private struct Attachment {
        let id: UUID
        let provider: NSItemProvider
        var job: StoredPrintJob?
        var error: String?
    }
    @Published private(set) var isWorking = false
    @Published private(set) var successCount = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var fileURL: URL?
    @Published private(set) var message = "PDF를 가져오는 중입니다."
    private let importer: ProviderPDFImporter
    private var attachments: [Attachment] = []
    private var progress: [UUID: Progress] = [:]
    private var cancellation = PDFImportCancellation()
    private var generation = UUID()
    var canClose: Bool { !isWorking }
    var canRetry: Bool { !isWorking && failedCount > 0 && !attachments.isEmpty }

    init(importer: ProviderPDFImporter = ProviderPDFImporter()) { self.importer = importer }
    func start(_ providers: [NSItemProvider]) {
        precondition(Thread.isMainThread)
        guard !isWorking else { return }
        attachments = providers.map { Attachment(id: UUID(), provider: $0) }
        totalCount = providers.count
        if providers.isEmpty { message = "가져올 PDF 첨부 파일이 없습니다."; failedCount = 1; return }
        runPending()
    }
    func retryFailed() {
        precondition(Thread.isMainThread)
        guard canRetry else { return }
        runPending()
    }
    private func runPending() {
        cancellation = PDFImportCancellation()
        generation = UUID()
        let run = generation
        let token = cancellation
        progress.removeAll()
        for index in attachments.indices where attachments[index].job == nil { attachments[index].error = nil }
        isWorking = true
        updateSummary()
        for attachment in attachments where attachment.job == nil {
            progress[attachment.id] = importer.load(attachment.provider, id: attachment.id, cancellation: token) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self, self.generation == run,
                          let index = self.attachments.firstIndex(where: { $0.id == attachment.id }),
                          self.attachments[index].job == nil, self.attachments[index].error == nil else { return }
                    switch result {
                    case .success(let job): self.attachments[index].job = job; self.fileURL = URL(string: job.urlString)
                    case .failure(let error): self.attachments[index].error = error.localizedDescription
                    }
                    self.progress.removeValue(forKey: attachment.id)
                    self.updateSummary()
                }
            }
        }
    }
    private func updateSummary() {
        successCount = attachments.filter { $0.job != nil }.count
        failedCount = attachments.filter { $0.error != nil }.count
        isWorking = successCount + failedCount < totalCount
        if isWorking { message = "PDF 가져오는 중: \(successCount + failedCount)/\(totalCount)" }
        else if failedCount > 0 {
            let reason = attachments.compactMap { $0.error }.first ?? "가져오기에 실패했습니다."
            message = "\(successCount)개 추가, \(failedCount)개 실패. \(reason) 실패한 첨부만 다시 시도할 수 있습니다."
        } else { message = "\(successCount)개 문서를 프린트 목록에 추가했습니다." }
    }
    func cancel() {
        precondition(Thread.isMainThread)
        // This waits for any commit already in progress and prevents all future commits.
        cancellation.cancel()
        generation = UUID()
        progress.values.forEach { $0.cancel() }
        progress.removeAll()
        // A commit can finish before its main-queue callback; include those successes.
        let committed = (try? importer.store.read()) ?? []
        for index in attachments.indices where attachments[index].job == nil {
            if let job = committed.first(where: { $0.id == attachments[index].id }) { attachments[index].job = job }
            else { attachments[index].error = PrintQueueError.cancelled.localizedDescription }
        }
        updateSummary()
        message = "가져오기를 취소했습니다. 이미 추가된 \(successCount)개 문서는 보존됩니다."
    }
}
