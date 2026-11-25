import SwiftUI

/// 文件预览：视频、音频、图片、PDF 与通用下载。
struct FilePreviewView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let entry: FileEntry

    @State private var shareItem: ShareItem?
    @State private var downloading = false
    @State private var preparingLink = false
    @State private var playbackLink: PlaybackLink?

    private enum Kind {
        case video
        case audio
        case image
        case pdf
        case other
    }

    private var kind: Kind {
        let mime = entry.mime ?? ""
        if mime.hasPrefix("video/") { return .video }
        if mime.hasPrefix("audio/") { return .audio }
        if mime.hasPrefix("image/") { return .image }
        if mime == "application/pdf" { return .pdf }
        return .other
    }

    private var inlineURL: URL? {
        app.api?.contentURL(path: entry.path, inline: true)
    }

    private var isMedia: Bool {
        kind == .video || kind == .audio
    }

    var body: some View {
        NavigationStack {
            Group {
                if let inlineURL {
                    switch kind {
                    case .video:
                        VStack(spacing: 0) {
                            VideoPlayerScreen(url: inlineURL)
                            mediaFooter(note: "部分编码（如部分 mkv）可能无法播放，可直接交给外部播放器。")
                        }
                    case .audio:
                        VStack(spacing: 0) {
                            ScrollView {
                                AudioPlayerScreen(url: inlineURL)
                            }
                            mediaFooter(note: "可交给外部播放器在后台播放或处理更多格式。")
                        }
                    case .image:
                        AuthenticatedImage(url: inlineURL)
                    case .pdf:
                        PDFPreviewScreen(url: inlineURL)
                    case .other:
                        otherView
                    }
                } else {
                    ContentUnavailableView("无法预览", systemImage: "exclamationmark.triangle")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if isMedia {
                        Button {
                            preparePlaybackLink()
                        } label: {
                            if preparingLink {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.up.forward.app")
                            }
                        }
                        .disabled(preparingLink)
                        .accessibilityLabel("用外部播放器打开")
                    }
                    Button {
                        download()
                    } label: {
                        if downloading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .disabled(downloading)
                    .accessibilityLabel("下载文件")
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $playbackLink) { link in
                PlaybackOptionsSheet(link: link)
            }
        }
    }

    private var otherView: some View {
        ContentUnavailableView {
            Label("该文件类型不支持在线预览", systemImage: "doc")
        } description: {
            Text("可下载后在支持的应用中打开。")
        } actions: {
            Button("下载文件") { download() }
                .primaryAction()
        }
    }

    private func mediaFooter(note: String) -> some View {
        HStack(spacing: 10) {
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button {
                preparePlaybackLink()
            } label: {
                Label("外部播放器", systemImage: "arrow.up.forward.app")
            }
            .inlineAction()
            .disabled(preparingLink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func preparePlaybackLink() {
        guard !preparingLink, let api = app.api else { return }
        preparingLink = true
        Task {
            do {
                let share = try await api.createShareLink(path: entry.path)
                guard let url = api.shareURL(token: share.token) else {
                    throw APIError.invalidServer
                }
                playbackLink = PlaybackLink(
                    url: url,
                    filename: entry.name,
                    expiresAt: share.expiresAt
                )
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            preparingLink = false
        }
    }

    private func download() {
        guard !downloading, let api = app.api else { return }
        downloading = true
        Task {
            do {
                let remote = api.contentURL(path: entry.path, inline: false)
                let local = try await FileDownloader.download(url: remote, filename: entry.name)
                shareItem = ShareItem(url: local)
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            downloading = false
        }
    }
}
