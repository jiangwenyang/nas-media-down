import SwiftUI

/// 目录导航目标。
struct DirectoryRoute: Hashable {
    let path: String
    let name: String
}

/// 下载目录浏览。根视图自带导航栈，子目录复用同一栈。
struct FileBrowserView: View {
    @Environment(AppState.self) private var app

    let path: String
    let title: String
    var isRoot = true

    @State private var listing: FileListing?
    @State private var loading = false
    @State private var error: String?
    @State private var preview: FileEntry?
    @State private var pendingDelete: FileEntry?
    @State private var shareItem: ShareItem?
    @State private var downloadingPath: String?
    @State private var preparingLinkPath: String?
    @State private var playbackLink: PlaybackLink?

    var body: some View {
        if isRoot {
            NavigationStack {
                content
                    .navigationDestination(for: DirectoryRoute.self) { route in
                        FileBrowserView(path: route.path, title: route.name, isRoot: false)
                    }
            }
        } else {
            content
                .navigationDestination(for: DirectoryRoute.self) { route in
                    FileBrowserView(path: route.path, title: route.name, isRoot: false)
                }
        }
    }

    private var content: some View {
        List {
            if let error {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        ErrorNotice(text: error)
                        Button("重新加载") { Task { await load() } }
                            .secondaryAction()
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if loading && listing == nil {
                    ForEach(0..<5, id: \.self) { _ in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 26, height: 26)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 14)
                        }
                        .padding(.vertical, 4)
                    }
                } else if let listing {
                    ForEach(listing.entries) { entry in
                        row(entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .refreshable { await load() }
        .task(id: path) { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
                .accessibilityLabel("刷新")
            }
        }
        .overlay {
            if !loading, let listing, listing.entries.isEmpty, error == nil {
                ContentUnavailableView(
                    "这个目录还是空的",
                    systemImage: "folder",
                    description: Text("下载完成的视频会出现在这里")
                )
            }
        }
        .sheet(item: $preview) { entry in
            FilePreviewView(entry: entry)
        }
        .sheet(item: $playbackLink) { link in
            PlaybackOptionsSheet(link: link)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "删除文件",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let entry = pendingDelete {
                    delete(entry)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.isDir == true
                ? "将递归删除该目录及其中所有文件，删除后不可恢复。"
                : "该文件将被永久删除，删除后不可恢复。")
        }
    }

    @ViewBuilder
    private func row(_ entry: FileEntry) -> some View {
        if entry.isDir {
            NavigationLink(value: DirectoryRoute(path: entry.path, name: entry.name)) {
                entryRow(entry)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingDelete = entry
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } else {
            Button {
                if isMedia(entry) {
                    requestPlayback(entry)
                } else {
                    open(entry)
                }
            } label: {
                entryRow(entry)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingDelete = entry
                } label: {
                    Label("删除", systemImage: "trash")
                }
                Button {
                    download(entry)
                } label: {
                    Label("下载", systemImage: "square.and.arrow.down")
                }
                .tint(Theme.accent)
                if isMedia(entry) {
                    Button {
                        requestPlayback(entry)
                    } label: {
                        Label("外部播放", systemImage: "arrow.up.forward.app")
                    }
                    .tint(Theme.accent)
                }
                if entry.isPreviewable {
                    Button {
                        preview = entry
                    } label: {
                        Label("预览", systemImage: "eye")
                    }
                    .tint(.secondary)
                }
            }
            .contextMenu {
                if entry.isPreviewable {
                    Button {
                        preview = entry
                    } label: {
                        Label("在线预览", systemImage: "eye")
                    }
                }
                if isMedia(entry) {
                    Button {
                        requestPlayback(entry)
                    } label: {
                        Label("用外部播放器打开", systemImage: "arrow.up.forward.app")
                    }
                }
                Button {
                    download(entry)
                } label: {
                    Label("下载到本地", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) {
                    pendingDelete = entry
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func entryRow(_ entry: FileEntry) -> some View {
        HStack(spacing: 12) {
            let icon = icon(for: entry)
            Image(systemName: icon.name)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(icon.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(entry.isDir ? "文件夹" : Format.bytes(entry.size))
                    if !entry.isDir {
                        Text("·")
                        Text(Format.date(entry.mtime))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if downloadingPath == entry.path || preparingLinkPath == entry.path {
                ProgressView()
                    .controlSize(.small)
            } else if !entry.isDir && isMedia(entry) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.1), in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func isMedia(_ entry: FileEntry) -> Bool {
        let mime = entry.mime ?? ""
        return mime.hasPrefix("video/") || mime.hasPrefix("audio/")
    }

    private func icon(for entry: FileEntry) -> (name: String, tint: Color) {
        if entry.isDir {
            return ("folder.fill", Color.secondary)
        }
        let mime = entry.mime ?? ""
        if mime.hasPrefix("video/") { return ("play.rectangle.fill", Theme.accent) }
        if mime.hasPrefix("audio/") { return ("waveform", Color.secondary) }
        if mime.hasPrefix("image/") { return ("photo.fill", Theme.success) }
        if mime == "application/pdf" { return ("doc.text.fill", Theme.danger) }
        if mime.hasPrefix("text/") { return ("doc.text.fill", .secondary) }
        return ("doc.fill", .secondary)
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let api = try app.requireAPI()
            listing = try await api.listFiles(path: path)
        } catch {
            self.error = APIError.describe(error)
        }
    }

    private func open(_ entry: FileEntry) {
        if entry.isPreviewable {
            preview = entry
        } else {
            download(entry)
        }
    }

    private func download(_ entry: FileEntry) {
        guard downloadingPath == nil else { return }
        downloadingPath = entry.path
        Task {
            do {
                let api = try app.requireAPI()
                let remote = api.contentURL(path: entry.path, inline: false)
                let local = try await FileDownloader.download(url: remote, filename: entry.name)
                shareItem = ShareItem(url: local)
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            downloadingPath = nil
        }
    }

    private func requestPlayback(_ entry: FileEntry) {
        guard preparingLinkPath == nil else { return }
        preparingLinkPath = entry.path
        Task {
            do {
                let api = try app.requireAPI()
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
            preparingLinkPath = nil
        }
    }

    private func delete(_ entry: FileEntry) {
        Task {
            do {
                let api = try app.requireAPI()
                try await api.deleteFile(path: entry.path, recursive: entry.isDir)
                app.showToast("已删除", style: .success)
                await load()
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
        }
    }
}
