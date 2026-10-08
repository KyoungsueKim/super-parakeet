import Foundation
import PDFKit
import Combine

var failures = 0
var checks = 0
func check(_ name: String, _ value: Bool) {
    checks += 1
    if value { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
}
let fm = FileManager.default
let testRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PDF_TEST_ROOT"]!)
func root(_ name: String) throws -> URL {
    let result = testRoot.appendingPathComponent(name)
    try fm.createDirectory(at: result, withIntermediateDirectories: true)
    return result
}
func pdf(_ text: String) -> Data {
    let page = PDFPage()
    let document = PDFDocument(); document.insert(page, at: 0)
    // Valid synthetic PDFs with distinguishable metadata; no personal input is read.
    document.documentAttributes = [PDFDocumentAttribute.titleAttribute: text]
    return document.dataRepresentation()!
}
func pump(_ condition: () -> Bool, timeout: TimeInterval = 8) {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    check("async operation completed", condition())
}
final class MutableData {
    private let lock = NSLock(); private var value: Data
    init(_ value: Data) { self.value = value }
    func set(_ data: Data) { lock.lock(); value = data; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return value }
}
func provider(_ data: MutableData, name: String = "same.pdf") -> NSItemProvider {
    let p = NSItemProvider(); p.suggestedName = name
    p.registerDataRepresentation(forTypeIdentifier: "com.adobe.pdf", visibility: .all) { completion in
        completion(data.get(), nil); return nil
    }
    return p
}
final class DelayedRepresentation {
    private let lock = NSLock()
    private var completion: ((Data?, Error?) -> Void)?
    let provider = NSItemProvider()
    init() {
        provider.suggestedName = "slow.pdf"
        provider.registerDataRepresentation(forTypeIdentifier: "com.adobe.pdf", visibility: .all) { callback in
            self.lock.lock(); self.completion = callback; self.lock.unlock()
            return Progress(totalUnitCount: 1)
        }
    }
    var waiting: Bool { lock.lock(); defer { lock.unlock() }; return completion != nil }
    func release(_ data: Data) { lock.lock(); let callback = completion; completion = nil; lock.unlock(); callback?(data, nil) }
}
final class LegacyDefaults: UserDefaults {
    let urls: [String]; let settingsData: Data?
    init(urls: [String], settings: Data?) {
        self.urls = urls; settingsData = settings
        super.init(suiteName: "PDFImportRegression-in-memory")!
    }
    override func stringArray(forKey key: String) -> [String]? { key == "printQueue" ? urls : nil }
    override func data(forKey key: String) -> Data? { key == "printQueueSettings" ? settingsData : nil }
}

if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--writer" {
    let store = SharedPrintJobStore(root: URL(fileURLWithPath: CommandLine.arguments[2]), legacyDefaults: nil)
    for i in 0..<15 { _ = try store.importPDF(data: pdf("\(CommandLine.arguments[3])-\(i)"), name: "same.pdf") }
    exit(0)
}

let store = SharedPrintJobStore(root: try root("core"), legacyDefaults: nil)
let a = try store.importPDF(data: pdf("first"), name: "same.pdf")
let b = try store.importPDF(data: pdf("second"), name: "same.pdf")
check("same name keeps independent UUIDs and paths", a.id != b.id && a.urlString != b.urlString)
check("same name preserves first PDF contents", PDFDocument(url: URL(string:a.urlString)!)?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "first")
check("same name preserves second PDF contents", PDFDocument(url: URL(string:b.urlString)!)?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "second")
_ = try store.importPDF(data: pdf("retry"), name: "same.pdf", id: a.id)
check("retry of committed UUID is idempotent", try store.read().count == 2)
let app = PrintJobQueue(store: store)
let other = PrintJobQueue(store: SharedPrintJobStore(root: try root("core"), legacyDefaults:nil))
let c = try store.importPDF(data: pdf("new"), name: "third.pdf")
app.setA3(true, for: a.urlString)
check("stale setting mutation preserves concurrent import", try store.read().count == 3)
app.reload(); other.reload()
check("warm reload sees committed import", app.jobs().contains(c.urlString))
let cold = PrintJobQueue(store: SharedPrintJobStore(root: try root("core"),legacyDefaults:nil))
check("cold cache sees durable queue", cold.jobs().count == 3)
let beforeReload = try Data(contentsOf:(try root("core")).appendingPathComponent("PrintQueue-v1/manifest.json"))
app.reload()
let afterReload = try Data(contentsOf:(try root("core")).appendingPathComponent("PrintQueue-v1/manifest.json"))
check("reload never rewrites manifest", beforeReload == afterReload)
check("one upload session across scenes", app.beginUpload() && !other.beginUpload())
try app.acknowledgeUpload(id:a.id,count:1)
check("upload acknowledgement preserves new documents", try store.read().contains { $0.id == c.id })
check("inflight upload file retained until session ends", fm.fileExists(atPath:URL(string:a.urlString)!.path))
app.endUpload()
check("owned uploaded PDF reclaimed after drain", !fm.fileExists(atPath:URL(string:a.urlString)!.path))
app.setJobQuantity(3,for:b.urlString)
try app.acknowledgeUpload(id:b.id,count:1)
check("partial success subtracts only confirmed copy", app.jobQuantity(for:b.urlString)==2)
let unplanned = try store.importPDF(data:pdf("unplanned"),name:"new.pdf")
app.removeAllJobs()
check("snapshot clear retains unseen new import", try store.read().contains { $0.id == unplanned.id })

let migrationRoot = try root("migration")
let legacyURL = migrationRoot.appendingPathComponent("original.pdf")
try pdf("legacy").write(to:legacyURL)
let legacy=LegacyDefaults(urls:[legacyURL.absoluteString,legacyURL.absoluteString],settings:Data("malformed".utf8))
let migrated=SharedPrintJobStore(root:migrationRoot,legacyDefaults:legacy)
let legacyJobs = try migrated.read()
check("malformed legacy settings recovers valid document queue",legacyJobs.count==1 && legacyJobs[0].settings.quantity==2)
check("migration UUID stable on subsequent reads",try migrated.read().first?.id==legacyJobs.first?.id)
_ = try migrated.transaction { $0.removeAll() }
try migrated.garbageCollect()
check("migration does not delete original file", fm.fileExists(atPath:legacyURL.path))
check("empty manifest prevents legacy resurrection", try migrated.read().isEmpty)
let corruptRoot=try root("corrupt")
let corrupt=SharedPrintJobStore(root:corruptRoot,legacyDefaults:nil)
_ = try corrupt.read()
let manifest=corruptRoot.appendingPathComponent("PrintQueue-v1/manifest.json")
try Data("corrupt".utf8).write(to:manifest)
do { _ = try corrupt.importPDF(data:pdf("blocked"),name:"x.pdf"); check("corrupt manifest fails safely",false) }
catch { check("corrupt manifest fails safely",true) }
check("corrupt manifest not silently overwritten", try Data(contentsOf:manifest)==Data("corrupt".utf8))

let providerStore=SharedPrintJobStore(root:try root("provider"),legacyDefaults:nil)
let session=ShareImportSession(importer:ProviderPDFImporter(store:providerStore))
let valid=MutableData(pdf("data")); let invalid=MutableData(Data("invalid".utf8))
session.start([provider(valid),provider(invalid)])
check("Close blocked for pending attachments",!session.canClose)
pump { !session.isWorking }
check("multiple attachments exposes partial failure",session.successCount==1 && session.failedCount==1 && session.canRetry)
invalid.set(pdf("recovered")); session.retryFailed(); pump { !session.isWorking }
check("retry imports only failed attachment",session.successCount==2 && session.failedCount==0 && (try? providerStore.read().count)==2)
check("PDF Data representation imported durably", (try? providerStore.read().allSatisfy { fm.fileExists(atPath:URL(string:$0.urlString)!.path) })==true)
let fileSource=(try root("provider")).appendingPathComponent("file-source.pdf")
try pdf("file-representation").write(to:fileSource)
let fileProvider=NSItemProvider(contentsOf:fileSource)!
fileProvider.suggestedName="file-source.pdf"
let fileSession=ShareImportSession(importer:ProviderPDFImporter(store:providerStore))
fileSession.start([fileProvider]); pump { !fileSession.isWorking }
check("file representation imported before source expires",fileSession.successCount==1 && (try? providerStore.read().count)==3)
let slow=DelayedRepresentation()
let slowSession=ShareImportSession(importer:ProviderPDFImporter(store:providerStore))
slowSession.start([slow.provider]); pump { slow.waiting }
check("slow provider cannot prematurely close",!slowSession.canClose)
slowSession.cancel()
check("cancel allows UI exit",slowSession.canClose && !slowSession.isWorking)
slow.release(pdf("late"))
RunLoop.current.run(until:Date().addingTimeInterval(0.25))
check("late callback after cancel cannot publish",(try? providerStore.read().count)==3)
let token=PDFImportCancellation(); token.cancel()
do { _ = try providerStore.importPDF(data:pdf("cancel"),name:"cancel.pdf",cancellation:token); check("cancelled commit rejected",false) }
catch { check("cancelled commit rejected",true) }

let multiRoot=try root("multiprocess")
let children=(0..<4).map { i -> Process in
    let p=Process(); p.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]); p.arguments=["--writer",multiRoot.path,String(i)]
    return p
}
for p in children { try p.run() }
for p in children { p.waitUntilExit(); check("writer process succeeded",p.terminationStatus==0) }
let all = try SharedPrintJobStore(root:multiRoot,legacyDefaults:nil).read()
check("four processes preserve all 60 same-name imports",all.count==60 && Set(all.map { $0.id }).count==60)
check("atomic queue never references missing PDF",all.allSatisfy { fm.fileExists(atPath:URL(string:$0.urlString)!.path) })

// The request client is a test double; no HTTP request or real print is sent.
actor FakeUploadClient: UploadRequesting {
    let failID: String?
    init(failID: String? = nil) { self.failID = failID }
    func upload(job: UploadJob, phoneNumber: String) async throws {
        if job.id==failID { throw PrintQueueError.invalidPDF }
        // Model an already-completed server response arriving after peer cancellation.
        try? await Task.sleep(nanoseconds:30_000_000)
    }
}
var asyncDone=false
Task { @MainActor in
    do {
        let uploadStore=SharedPrintJobStore(root:try root("upload"),legacyDefaults:nil)
        let first=try uploadStore.importPDF(data:pdf("planned"),name:"planned.pdf")
        let q=PrintJobQueue(store:uploadStore)
        let vm=UploadStatusViewModel(queue:q,useCase:UploadJobsUseCase(uploader:FakeUploadClient()))
        vm.start(phoneNumber:"synthetic")
        let new=try uploadStore.importPDF(data:pdf("new-during-upload"),name:"new.pdf")
        let overlap=UploadStatusViewModel(queue:q,useCase:UploadJobsUseCase(uploader:FakeUploadClient()))
        overlap.start(phoneNumber:"synthetic")
        check("overlapping upload cannot replan same IDs",overlap.state == .FAILED)
        for _ in 0..<500 where vm.state == .PROGRESS { try await Task.sleep(nanoseconds:10_000_000) }
        check("successful planned upload finishes",vm.state == .SUCCESS)
        let left=try uploadStore.read()
        check("upload during new share removes only planned success",left.count==1 && left[0].id==new.id && !left.contains { $0.id==first.id })
        let fail=try uploadStore.importPDF(data:pdf("failed"),name:"failed.pdf")
        q.reload()
        let partial=UploadStatusViewModel(queue:q,useCase:UploadJobsUseCase(uploader:FakeUploadClient(failID:fail.id.uuidString)))
        partial.start(phoneNumber:"synthetic")
        for _ in 0..<500 where partial.state == .PROGRESS { try await Task.sleep(nanoseconds:10_000_000) }
        let remaining=try uploadStore.read()
        check("partial upload reports failure",partial.state == .FAILED)
        check("failure drain acknowledges successful peers",remaining.count==1 && remaining[0].id==fail.id)
        let cancelling=UploadStatusViewModel(queue:q,useCase:UploadJobsUseCase(uploader:FakeUploadClient()))
        cancelling.start(phoneNumber:"synthetic")
        // Cancellation after the request starts exercises success-draining behavior.
        try await Task.sleep(nanoseconds:10_000_000)
        cancelling.cancel()
        let again=UploadStatusViewModel(queue:q,useCase:UploadJobsUseCase(uploader:FakeUploadClient()))
        again.start(phoneNumber:"synthetic")
        check("cancel blocks retry until old request drained",again.state == .FAILED)
        for _ in 0..<500 where cancelling.state == .PROGRESS { try await Task.sleep(nanoseconds:10_000_000) }
        check("cancelled session releases global upload guard",q.beginUpload()); q.endUpload()
    } catch { failures += 1; print("FAIL unexpected async error \(error)") }
    asyncDone=true
}
pump({asyncDone},timeout:15)
print("RESULT \(checks) checks, \(failures) failures")
exit(failures==0 ? 0 : 1)
