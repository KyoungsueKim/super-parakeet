//
//  ShareViewController.swift
//  super-parakeet-sharext
//
//  Created by 김경수 on 2022/08/17.
//

import Foundation
import UIKit
import SwiftUI
import MobileCoreServices

class FileURL: ObservableObject {
    @Published var fileURL: URL?
}

class ShareViewController: UIViewController {
    var fileURL = FileURL()
    private let appGroupIdentifier = "group.KyoungsueKim.printer"
    
    @IBSegueAction func showSwiftUIView(_ coder: NSCoder) -> UIViewController? {
        return UIHostingController(coder: coder, rootView: SwiftUIView().environmentObject(fileURL))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let item = extensionContext?.inputItems.first as? NSExtensionItem {
            getFileURL(extensionItem: item)
        }

        // at the end of viewDidLoad
        NotificationCenter.default.addObserver(forName: .shareExtensionDidRequestClose, object: nil, queue: nil) { _ in
            self.close()
        }
    }
    
    private func getFileURL(extensionItem: NSExtensionItem) {
        guard let attachments = extensionItem.attachments, attachments.isEmpty == false else {
            return
        }

        let supportedTypeIdentifiers = ["public.file-url", "com.adobe.pdf"]
        for attachment in attachments {
            guard let identifier = supportedTypeIdentifiers.first(where: attachment.hasItemConformingToTypeIdentifier) else {
                continue
            }

            attachment.loadItem(forTypeIdentifier: identifier, options: nil) { [weak self] item, _ in
                guard let self = self else { return }
                guard let sourceURL = item as? URL else { return }
                self.copyToSharedContainer(from: sourceURL)
            }
        }
    }

    /// 공유된 파일을 App Group 컨테이너로 복사합니다.
    /// - Parameter sourceURL: 공유 확장에서 전달된 원본 파일 URL.
    private func copyToSharedContainer(from sourceURL: URL) {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = sharedContainerURL.appendingPathComponent(sourceURL.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            DispatchQueue.main.async { [weak self] in
                self?.fileURL.fileURL = destinationURL
                PrintJobQueue.shared.addJob(url: destinationURL.absoluteString)
            }
        } catch {
            return
        }
    }
    
    // add this function to UIShareViewController
    func close() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

extension Notification.Name {
    /// 공유 확장 닫기 요청 알림입니다.
    static let shareExtensionDidRequestClose = Notification.Name("shareExtensionDidRequestClose")
}
