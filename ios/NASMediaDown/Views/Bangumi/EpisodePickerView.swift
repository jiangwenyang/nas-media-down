import SwiftUI

/// 剧集选集下载。
struct EpisodePickerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let seasonId: Int
    let title: String
    let subscribed: Bool
    let onDownload: ([Int]) async throws -> Void

    @State private var detail: BangumiSeasonDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""
    @State private var selected: Set<Int> = []
    @State private var submitting = false
    @State private var submitError: String?

    private var episodes: [BangumiSeasonEpisode] {
        detail?.episodes ?? []
    }

    private var filtered: [BangumiSeasonEpisode] {
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return episodes }
        return episodes.filter {
            $0.title.lowercased().contains(keyword)
                || ($0.longTitle ?? "").lowercased().contains(keyword)
        }
    }

    private var selectableFiltered: [BangumiSeasonEpisode] {
        filtered.filter(isSelectable)
    }

    private var allSelected: Bool {
        !selectableFiltered.isEmpty && selectableFiltered.allSatisfy { selected.contains($0.idx) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("正在加载剧集…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("无法加载剧集", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await load() } }
                            .secondaryAction()
                    }
                } else {
                    List {
                        Section {
                            ForEach(filtered) { episode in
                                row(episode)
                            }
                        } header: {
                            Text("已选 \(selected.count) 集 · 共 \(episodes.count) 集")
                        } footer: {
                            if !subscribed {
                                Text("未追更：本次只下载所选剧集，不会自动跟踪后续更新。")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if filtered.isEmpty {
                            ContentUnavailableView(
                                "没有匹配的剧集",
                                systemImage: "magnifyingglass",
                                description: Text("换个关键词试试")
                            )
                        }
                    }
                }
            }
            .searchable(
                text: $search,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索剧集标题"
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(submitting)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(allSelected ? "取消全选" : "全选可下载") {
                        toggleAll()
                    }
                    .disabled(selectableFiltered.isEmpty || submitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .task(id: seasonId) { await load() }
            .interactiveDismissDisabled(submitting)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let submitError {
                ErrorNotice(text: submitError)
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 6) {
                    if submitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.onInk)
                    }
                    Text(submitting ? "正在创建…" : "下载选中 \(selected.count) 集")
                        .frame(maxWidth: .infinity)
                }
            }
            .primaryAction()
            .disabled(submitting || selected.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func row(_ episode: BangumiSeasonEpisode) -> some View {
        let selectable = isSelectable(episode)
        let style = StatusStyle.episode(episode.status)

        return Button {
            guard selectable else { return }
            toggle(episode.idx)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected.contains(episode.idx) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        !selectable
                            ? Color.secondary.opacity(0.25)
                            : (selected.contains(episode.idx) ? Theme.accent : Color.secondary.opacity(0.4))
                    )

                Text("\(episode.idx)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let long = episode.longTitle, long != episode.title {
                        Text(long)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                Text(Format.duration(episode.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let style {
                    Text(style.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(style.tint)
                        .frame(width: 52, alignment: .trailing)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .opacity(selectable ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!selectable || submitting)
    }

    private func isSelectable(_ episode: BangumiSeasonEpisode) -> Bool {
        episode.status != .done && episode.status != .queued
    }

    private func toggle(_ index: Int) {
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }

    private func toggleAll() {
        if allSelected {
            selectableFiltered.forEach { selected.remove($0.idx) }
        } else {
            selectableFiltered.forEach { selected.insert($0.idx) }
        }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let api = try app.requireAPI()
            detail = try await api.bangumiSeason(id: seasonId)
        } catch {
            self.error = APIError.describe(error)
        }
    }

    private func submit() {
        guard !submitting, !selected.isEmpty else { return }
        submitting = true
        submitError = nil
        let indices = selected.sorted()
        Task {
            do {
                try await onDownload(indices)
                dismiss()
            } catch {
                submitError = APIError.describe(error)
                submitting = false
            }
        }
    }
}
