//
//  ShareView.swift
//  super-parakeet-sharext
//
//  Created by 김경수 on 2022/08/23.
//

import Foundation
import SwiftUI
import PDFKit
import AVFoundation

struct SwiftUIView: View {
    @EnvironmentObject var fileURL: FileURL
    
    var body: some View {
        VStack (spacing: 15){
            let icon = fileURL.fileURL != nil ? "checkmark.circle" : "clear"
            Image(systemName: icon)
                .resizable()
                .frame(width: 80, height: 80, alignment: .center)
                .padding(.top, 100)
                .onAppear(){
                    HapticManager.instance.notification(type: .success)
                    AudioServicesPlaySystemSound(1407)
                }

            let headMessage = fileURL.fileURL != nil ? "Successfully added to printing lists" : "Failed to add printing lists"
            Text(headMessage)
                .modifier(TextModifier(font: UIConfiguration.titleFont,
                                   color: UIConfiguration.ajouColor))
            
            let bodyMessage = fileURL.fileURL != nil ? "어플리케이션을 실행하고 휴대폰 번호를 입력 후 Print 버튼을 눌러주세요." : "파일 로드에 문제가 발생했습니다. 다시 한번 시도해보세요."
            Text(bodyMessage)
                .modifier(TextModifier(font: UIConfiguration.middleFont))
                .padding(.horizontal, 60)
            
            Button(action: {
                self.close()
            }) {
                Text("Close")
                    .modifier(ButtonModifier(font: UIConfiguration.buttonFont,
                                             color: UIConfiguration.ajouColor,
                                             textColor: .white,
                                             width: 100,
                                             height: 35,
                                             cornerRadious: 10))
            }
            
            if let url = fileURL.fileURL {
                PDFKitRepresentedView(url: url)
            }
            
            Spacer()

        }
    }
    
    func close() {
        NotificationCenter.default.post(name: NSNotification.Name("close"), object: nil)
    }
}

struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func makeUIView(context: UIViewRepresentableContext<PDFKitRepresentedView>) -> PDFKitRepresentedView.UIViewType {
        // Create a `PDFView` and set its `PDFDocument`.
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: self.url)
        pdfView.autoScales = true
        pdfView.goToFirstPage(nil)
        return pdfView
    }

    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<PDFKitRepresentedView>) {
        // Update the view.
    }
}
