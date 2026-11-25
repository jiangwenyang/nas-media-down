import SwiftUI
import UIKit

/// 统一文件预览：媒体通过 VidHub 打开或复制链接，图片与 PDF 保持内嵌预览。
struct FilePreviewView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let entry: FileEntry

    @State private var shareLink: ShareLink?
    @State private var preparing = false
    @State private var error: String?
    @State private var copied = false

    private enum Kind {
        case media
        case image
        case pdf
        case other
    }

    private var kind: Kind {
        if entry.isVideo || entry.isAudio { return .media }
        if entry.isImage { return .image }
        if entry.isPDF { return .pdf }
        return .other
    }

    private var inlineURL: URL? {
        app.api?.contentURL(path: entry.path, inline: true)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch kind {
                case .media:
                    mediaView
                case .image:
                    imageView
                case .pdf:
                    pdfView
                case .other:
                    otherView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task(id: entry.path) { await prepareLinkIfNeeded() }
        }
    }

    // MARK: - 媒体

    private var mediaView: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 24)

                Image(systemName: entry.isVideo ? "film" : "waveform")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 92, height: 92)
                    .background(
                        Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )

                VStack(spacing: 5) {
                    Text(entry.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    ErrorNotice(text: error)
                    Button("重试") {
                        Task { await prepareLinkIfNeeded(force: true) }
                    }
                    .secondaryAction()
                } else {
                    VStack(spacing: 10) {
                        Button {
                            openInVidHub()
                        } label: {
                            if preparing {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Theme.onInk)
                            } else {
                                Label("用 VidHub 打开", systemImage: "arrow.up.forward.app")
                            }
                        }
                        .primaryAction(fullWidth: true)
                        .disabled(preparing || shareLink == nil)

                        Button {
                            copyLink()
                        } label: {
                            Label(
                                copied ? "链接已复制" : "复制链接",
                                systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .secondaryAction()
                        .disabled(preparing || shareLink == nil)
                    }

                    Text("链接 6 小时内有效，MKV 等格式由 VidHub 解码。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 24)
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
    }

    private var subtitle: String {
        let parts = [Format.bytes(entry.size), entry.fileExtension.uppercased()]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - 图片与 PDF

    @ViewBuilder
    private var imageView: some View {
        if let inlineURL {
            AuthenticatedImage(url: inlineURL)
        } else {
            unavailable
        }
    }

    @ViewBuilder
    private var pdfView: some View {
        if let inlineURL {
            PDFPreviewScreen(url: inlineURL)
        } else {
            unavailable
        }
    }

    private var otherView: some View {
        ContentUnavailableView(
            "该文件类型不支持预览",
            systemImage: "doc",
            description: Text("可通过文件列表复制链接或使用其他工具打开。")
        )
    }

    private var unavailable: some View {
        ContentUnavailableView("无法预览", systemImage: "exclamationmark.triangle")
    }

    // MARK: - 链接

    private func prepareLinkIfNeeded(force: Bool = false) async {
        guard kind == .media else { return }
        if !force, shareLink != nil { return }
        guard !preparing else { return }

        preparing = true
        error = nil
        copied = false
        defer { preparing = false }

        do {
            let api = try app.requireAPI()
            shareLink = try await api.createShareLink(path: entry.path)
        } catch {
            self.error = APIError.describe(error)
        }
    }

    private func openInVidHub() {
        guard let remote = remoteURL else { return }
        guard let vidhub = ExternalPlayer.vidHubURL(for: remote),
              ExternalPlayer.isVidHubInstalled else {
            copyLink()
            app.showToast("未安装 VidHub，已复制链接", style: .info)
            return
        }
        ExternalPlayer.open(vidhub)
    }

    private func copyLink() {
        guard let remote = remoteURL else { return }
        UIPasteboard.general.string = remote.absoluteString
        copied = true
        app.showToast("链接已复制", style: .success)
    }

    private var remoteURL: URL? {
        guard let shareLink else { return nil }
        return app.api?.shareURL(token: shareLink.token)
    }
}
