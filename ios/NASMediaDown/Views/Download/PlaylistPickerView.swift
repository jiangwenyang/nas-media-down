import SwiftUI

/// 播放列表选择结果。
struct PlaylistSelection {
    enum Mode {
        case selected
        case all
        case current
    }

    let mode: Mode
    let entries: [PlaylistEntry]
}

/// 播放列表条目勾选。
struct PlaylistPickerView: View {
    let playlist: PlaylistInfo
    let currentVideo: VideoInfo?
    let onDownload: (PlaylistSelection) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var selected: Set<Int> = []
    @State private var submitting = false
    @State private var error: String?

    private var filtered: [PlaylistEntry] {
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return playlist.entries }
        return playlist.entries.filter { $0.title.lowercased().contains(keyword) }
    }

    private var allFilteredSelected: Bool {
        !filtered.isEmpty && filtered.allSatisfy { selected.contains($0.index) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered) { entry in
                        row(entry)
                    }
                } header: {
                    Text("共 \(playlist.count) 个视频 · 已选 \(selected.count) 个")
                } footer: {
                    if playlist.truncated {
                        Text("列表共 \(playlist.count) 个视频，当前仅加载前 \(playlist.entries.count) 个。")
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的视频",
                        systemImage: "magnifyingglass",
                        description: Text("换个关键词试试")
                    )
                }
            }
            .searchable(
                text: $search,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索视频标题"
            )
            .navigationTitle(playlist.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(submitting)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(allFilteredSelected ? "取消全选" : "全选") {
                        toggleAll()
                    }
                    .disabled(filtered.isEmpty || submitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .interactiveDismissDisabled(submitting)
        }
    }

    private func row(_ entry: PlaylistEntry) -> some View {
        Button {
            toggle(entry.index)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected.contains(entry.index) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected.contains(entry.index) ? Theme.accent : Color.secondary.opacity(0.4))

                Text("\(entry.index)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)

                RemoteImage(urlString: entry.thumbnail)
                    .frame(width: 72, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(entry.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(Format.duration(entry.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error {
                ErrorNotice(text: error)
            }

            if currentVideo != nil {
                Button {
                    submit(.current, entries: [])
                } label: {
                    Text("仅下载当前视频")
                        .frame(maxWidth: .infinity)
                }
                .secondaryAction()
                .disabled(submitting)
            }

            HStack(spacing: 10) {
                Button {
                    submit(.all, entries: playlist.entries)
                } label: {
                    Text("下载全部 \(playlist.entries.count) 个")
                        .frame(maxWidth: .infinity)
                }
                .secondaryAction()
                .disabled(submitting)

                Button {
                    submit(
                        .selected,
                        entries: playlist.entries.filter { selected.contains($0.index) }
                    )
                } label: {
                    HStack(spacing: 6) {
                        if submitting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.onInk)
                        }
                        Text(submitting ? "正在创建…" : "下载选中 \(selected.count) 个")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .primaryAction()
                .disabled(submitting || selected.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func toggle(_ index: Int) {
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }

    private func toggleAll() {
        if allFilteredSelected {
            filtered.forEach { selected.remove($0.index) }
        } else {
            filtered.forEach { selected.insert($0.index) }
        }
    }

    private func submit(_ mode: PlaylistSelection.Mode, entries: [PlaylistEntry]) {
        guard !submitting else { return }
        guard mode != .selected || !entries.isEmpty else { return }

        submitting = true
        error = nil
        Task {
            do {
                try await onDownload(PlaylistSelection(mode: mode, entries: entries))
                dismiss()
            } catch {
                self.error = APIError.describe(error)
                submitting = false
            }
        }
    }
}
