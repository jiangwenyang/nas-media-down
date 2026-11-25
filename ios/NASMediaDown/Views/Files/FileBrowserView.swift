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
                open(entry)
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
            }
            .contextMenu {
                if entry.isPreviewable {
                    Button {
                        preview = entry
                    } label: {
                        Label("预览", systemImage: "eye")
                    }
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
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func icon(for entry: FileEntry) -> (name: String, tint: Color) {
        if entry.isDir {
            return ("folder.fill", Color.secondary)
        }
        if entry.isVideo { return ("play.rectangle.fill", Theme.accent) }
        if entry.isAudio { return ("waveform", Color.secondary) }
        if entry.isImage { return ("photo.fill", Theme.success) }
        if entry.isPDF { return ("doc.text.fill", Theme.danger) }
        if (entry.mime ?? "").hasPrefix("text/") { return ("doc.text.fill", .secondary) }
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
            app.showToast("该文件类型暂不支持预览", style: .info)
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
