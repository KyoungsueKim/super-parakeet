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
    
    @IBSegueAction func showSwiftUIView(_ coder: NSCoder) -> UIViewController? {
        return UIHostingController(coder: coder, rootView: SwiftUIView().environmentObject(fileURL))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let item = extensionContext?.inputItems.first as? NSExtensionItem {
            getFileURL(extensionItem: item)
        }

        // at the end of viewDidLoad
        NotificationCenter.default.addObserver(forName: NSNotification.Name("close"), object: nil, queue: nil) { _ in
            self.close()
        }
    }
    
    private func getFileURL(extensionItem: NSExtensionItem) {
        var propertyList: String?
        for attachment in extensionItem.attachments! {
            if attachment.hasItemConformingToTypeIdentifier("public.file-url"){
                propertyList = "public.file-url"
            }
            else if attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                propertyList = "com.adobe.pdf"
            }
            
            if let identifier = propertyList {
                attachment.loadItem(
                    forTypeIdentifier: identifier,
                    options: nil,
                    completionHandler: { (item, error) -> Void in
                        if let data = item as? URL {
                            var sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.KyoungsueKim.printer")
                            
                            do{
                                let sharedFileUrl = ((sharedURL!.absoluteString) + (data.absoluteString as NSString).lastPathComponent)
                                if FileManager.default.fileExists(atPath: (URL(string: sharedFileUrl)!.path)){
                                    try FileManager.default.removeItem(at: URL(string: sharedFileUrl)!)
                                }
                                try FileManager.default.copyItem(at: data, to: URL(string: sharedFileUrl)!)
                                print(sharedFileUrl)
                                self.fileURL.fileURL = URL(string: sharedFileUrl)
                                PrintJobs.instance.AddJobs(url: sharedFileUrl)
                                PrintJobs.instance.objectWillChange.send()
                                
                            } catch {
                                return
                            }
                        }
                        
                    }
                )
            }
        }
    }
    
    // add this function to UIShareViewController
    func close() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

