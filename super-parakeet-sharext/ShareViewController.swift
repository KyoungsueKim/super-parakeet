import Foundation
import SwiftUI
import UIKit

class ShareViewController: UIViewController {
    let session = ShareImportSession()
    private var observers: [NSObjectProtocol] = []

    @IBSegueAction func showSwiftUIView(_ coder: NSCoder) -> UIViewController? {
        UIHostingController(coder: coder, rootView: SwiftUIView().environmentObject(session))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        session.start(providers)
        observers.append(NotificationCenter.default.addObserver(forName: .shareExtensionDidRequestClose, object: nil, queue: .main) { [weak self] _ in
            self?.close()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .shareExtensionDidRequestCancel, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.session.cancel()
            self.extensionContext?.cancelRequest(withError: PrintQueueError.cancelled)
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func close() {
        guard session.canClose else { return }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

extension Notification.Name {
    static let shareExtensionDidRequestClose = Notification.Name("shareExtensionDidRequestClose")
    static let shareExtensionDidRequestCancel = Notification.Name("shareExtensionDidRequestCancel")
}
