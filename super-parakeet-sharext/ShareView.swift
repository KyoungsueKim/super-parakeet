import Foundation
import SwiftUI
import PDFKit

struct SwiftUIView: View {
    @EnvironmentObject var session: ShareImportSession
    @State private var confirmCancel = false

    var body: some View {
        VStack(spacing: 15) {
            if session.isWorking { ProgressView().padding(.top, 60) }
            else {
                Image(systemName: session.failedCount == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                    .resizable().frame(width: 70, height: 70).padding(.top, 60)
            }
            Text(session.message)
                .modifier(TextModifier(font: UIConfiguration.middleFont))
                .padding(.horizontal, 30)
            if session.canRetry {
                Button("실패한 첨부 다시 시도") { session.retryFailed() }
            }
            Button("Close") {
                NotificationCenter.default.post(name: .shareExtensionDidRequestClose, object: nil)
            }
            .disabled(!session.canClose)
            if session.isWorking {
                Button("가져오기 취소") { confirmCancel = true }
            }
            if let url = session.fileURL { PDFKitRepresentedView(url: url) }
            Spacer()
        }
        .alert("가져오기를 취소할까요?", isPresented: $confirmCancel) {
            Button("계속 가져오기", role: .cancel) { }
            Button("취소하고 닫기", role: .destructive) {
                NotificationCenter.default.post(name: .shareExtensionDidRequestCancel, object: nil)
            }
        } message: {
            Text("이미 목록에 추가된 문서는 보존됩니다. 남은 첨부는 추가되지 않습니다.")
        }
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
        guard let pdfView = uiView as? PDFView else { return }
        if pdfView.document?.documentURL != url { pdfView.document = PDFDocument(url: url) }
    }
}
