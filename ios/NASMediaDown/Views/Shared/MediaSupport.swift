import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import PDFKit

/// 本地生成二维码图片。
enum QRCodeRenderer {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// 需要登录态的网络图片（文件预览用）。
struct AuthenticatedImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else if failed {
                ContentUnavailableView(
                    "图片加载失败",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("请检查服务器连接后重试")
                )
            } else {
                ProgressView()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        failed = false
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data)
            else {
                failed = true
                return
            }
            image = decoded
        } catch {
            failed = true
        }
    }
}

/// 远程 PDF 预览。
struct PDFPreviewScreen: View {
    let url: URL
    @State private var document: PDFDocument?
    @State private var failed = false

    var body: some View {
        Group {
            if let document {
                PDFKitRepresented(document: document)
            } else if failed {
                ContentUnavailableView(
                    "PDF 加载失败",
                    systemImage: "doc.richtext",
                    description: Text("请检查服务器连接后重试")
                )
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            document = nil
            failed = false
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let pdf = PDFDocument(data: data)
                else {
                    failed = true
                    return
                }
                document = pdf
            } catch {
                failed = true
            }
        }
    }
}

private struct PDFKitRepresented: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}
