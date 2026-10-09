import Foundation
import SwiftUI
import PDFKit

struct SwiftUIView: View {
    @EnvironmentObject var session: ShareImportSession
    @State private var confirmCancel = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if session.isWorking {
                    ProgressView().accessibilityLabel("문서 가져오는 중")
                } else {
                    Image(systemName: session.failedCount == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .accessibilityHidden(true)
                }
                Text(session.message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if session.canRetry {
                    Button { session.retryFailed() } label: {
                        Text("실패한 첨부 다시 시도")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    NotificationCenter.default.post(name: .shareExtensionDidRequestClose, object: nil)
                } label: {
                    Text("Close").frame(minHeight: 44).contentShape(Rectangle())
                }
                .disabled(!session.canClose)
                if session.isWorking {
                    Button { confirmCancel = true } label: {
                        Text("가져오기 취소").frame(minHeight: 44).contentShape(Rectangle())
                    }
                }
                if let url = session.fileURL {
                    PDFKitRepresentedView(url: url)
                        .frame(minHeight: 240)
                        .accessibilityLabel("가져온 PDF 미리보기")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
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
