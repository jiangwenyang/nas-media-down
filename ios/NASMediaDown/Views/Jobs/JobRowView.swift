import SwiftUI

/// 单条任务卡片：状态、进度、可展开条目与直接操作。
struct JobRowView: View {
    @Environment(AppState.self) private var app

    let job: Job
    var compact = false

    @State private var expanded: Bool
    @State private var detailItems: [JobItem]?
    @State private var loadingDetail = false
    @State private var busy = false
    @State private var confirmDelete = false

    init(job: Job, compact: Bool = false) {
        self.job = job
        self.compact = compact
        _expanded = State(initialValue: !compact && job.status.isActive)
    }

    private var statusStyle: StatusStyle { .job(job.status) }
    private var items: [JobItem] { job.items ?? detailItems ?? [] }
    private var activeItems: [JobItem] { items.filter { $0.status == .downloading } }
    private var activeSpeed: Double { activeItems.compactMap(\.speed).reduce(0, +) }
    private var activeEta: Double { activeItems.compactMap(\.eta).max() ?? 0 }
    private var doneCount: Int { items.filter { $0.status == .done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 12) {
            header

            if let error = job.error, !compact, !error.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(error)
                        .font(.caption)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.danger)
            }

            progressBlock

            if !compact && expanded && job.itemCount > 1 {
                itemsBlock
            }

            if !compact {
                actionBar
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !compact {
                if job.status.isActive {
                    Button(role: .destructive) {
                        cancelJob()
                    } label: {
                        Label("取消", systemImage: "xmark")
                    }
                } else {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }

                if job.status.canRetry {
                    Button {
                        retryJob()
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .tint(Theme.accent)
                }
            }
        }
        .confirmationDialog("删除任务记录", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) { deleteJob() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会移除任务历史，不会删除 NAS 上已下载的文件。")
        }
        .task(id: expanded) { await loadDetailIfNeeded() }
        .onChange(of: job.items == nil) { _, isNil in
            if isNil, expanded {
                Task { await loadDetailIfNeeded() }
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            statusGlyph

            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(metaText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            StatusBadge(
                text: statusStyle.label,
                tint: statusStyle.tint,
                showDot: job.status.isActive
            )
        }
    }

    private var statusGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            Image(systemName: statusStyle.symbol)
                .font(.system(size: compact ? 14 : 18, weight: .semibold))
                .foregroundStyle(statusStyle.tint)
        }
        .frame(width: compact ? 32 : 42, height: compact ? 32 : 42)
    }

    private var metaText: String {
        let kind = job.kind == .playlist ? "播放列表 · \(job.itemCount) 个" : "单视频"
        return "\(kind) · \(Format.date(job.createdAt))"
    }

    // MARK: - 进度

    private var progressBlock: some View {
        VStack(spacing: 7) {
            ProgressTrack(
                progress: job.progress,
                active: job.status.isActive,
                height: compact ? 5 : 8
            )

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Format.percent(job.progress))
                    .font(
                        compact
                            ? .subheadline.weight(.semibold).monospacedDigit()
                            : (job.status.isActive
                                ? .title2.weight(.bold).monospacedDigit()
                                : .title3.weight(.semibold).monospacedDigit())
                    )
                    .foregroundStyle(
                        job.status.isActive
                            ? Theme.accent
                            : (job.progress > 0 ? Color.primary : Color.secondary)
                    )
                    .contentTransition(.numericText())

                if job.status.isActive, let speed = Format.speed(activeSpeed) {
                    Text(speed)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                progressTrailing
            }
        }
    }

    @ViewBuilder
    private var progressTrailing: some View {
        if job.status.isActive {
            if activeEta > 0, let eta = Format.eta(activeEta) {
                Label(eta, systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(job.status == .queued ? "等待开始" : "正在下载")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let finished = job.finishedAt {
            Text(Format.date(finished))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 条目

    private var itemsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Text("条目")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if loadingDetail {
                    ProgressView()
                        .controlSize(.mini)
                } else if !items.isEmpty {
                    Text("\(doneCount)/\(job.itemCount) 已完成")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            if loadingDetail && items.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else {
                ForEach(items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: JobItem) -> some View {
        let style = StatusStyle.item(item.status)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                itemThumb(item)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(style.tint)
                            .frame(width: 4, height: 4)
                        Text(
                            item.status == .downloading
                                ? "\(style.label) · \(Format.percent(item.progress))"
                                : style.label
                        )
                        if item.totalBytes != nil {
                            Text("· \(Format.bytes(item.totalBytes))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if item.status == .failed || item.status == .cancelled {
                    Button {
                        retryItem(item)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 26, height: 26)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityLabel("重试该视频")
                }
            }

            if item.status == .downloading {
                ProgressTrack(progress: item.progress, active: true, height: 3)
                    .padding(.leading, 66)
            }

            if let error = item.error, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.danger.opacity(0.85))
                    .lineLimit(2)
                    .padding(.leading, 66)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func itemThumb(_ item: JobItem) -> some View {
        if let thumbnail = item.thumbnail, !thumbnail.isEmpty {
            RemoteImage(urlString: thumbnail)
                .frame(width: 56, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Text("\(item.idx)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 56, height: 32)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
        }
    }

    // MARK: - 操作

    private var actionBar: some View {
        VStack(spacing: 10) {
            Divider()

            HStack(spacing: 10) {
                if job.status.isActive {
                    Button {
                        cancelJob()
                    } label: {
                        Label("取消下载", systemImage: "stop.circle")
                    }
                    .destructiveAction(compact: true)
                    .disabled(busy)
                } else if job.status.canRetry {
                    Button {
                        retryJob()
                    } label: {
                        Label("重新下载", systemImage: "arrow.clockwise")
                    }
                    .secondaryAction(compact: true)
                    .disabled(busy)
                }

                if !job.status.isActive {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.danger.opacity(0.85))
                    .disabled(busy)
                }

                Spacer(minLength: 8)

                if job.itemCount > 1 {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            expanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(expanded ? "收起条目" : "展开 \(job.itemCount) 个条目")
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 动作

    private func loadDetailIfNeeded() async {
        guard expanded, job.items == nil, detailItems == nil, !loadingDetail, !compact else { return }
        loadingDetail = true
        defer { loadingDetail = false }
        do {
            let api = try app.requireAPI()
            detailItems = try await api.job(id: job.id).items
        } catch {
            app.showToast(APIError.describe(error), style: .error)
        }
    }

    private func cancelJob() {
        guard !busy else { return }
        busy = true
        Task {
            do {
                let api = try app.requireAPI()
                try await api.cancelJob(id: job.id)
                app.showToast("已请求取消任务", style: .info)
                await app.jobs.refresh()
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            busy = false
        }
    }

    private func deleteJob() {
        guard !busy else { return }
        busy = true
        Task {
            do {
                let api = try app.requireAPI()
                try await api.deleteJob(id: job.id)
                app.showToast("已删除任务记录", style: .success)
                await app.jobs.refresh()
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            busy = false
        }
    }

    private func retryJob() {
        guard !busy else { return }
        busy = true
        Task {
            do {
                var source = items
                if source.isEmpty {
                    let api = try app.requireAPI()
                    source = try await api.job(id: job.id).items
                }
                try await createJob(
                    api: try app.requireAPI(),
                    entries: source.map { entry(for: $0) }
                )
                app.showToast("已重新加入下载队列", style: .success)
                await app.jobs.refresh()
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            busy = false
        }
    }

    private func retryItem(_ item: JobItem) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                try await createJob(
                    api: try app.requireAPI(),
                    entries: [entry(for: item)]
                )
                app.showToast("已重新加入下载队列", style: .success)
                await app.jobs.refresh()
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            busy = false
        }
    }

    private func entry(for item: JobItem) -> JobItemInput {
        JobItemInput(
            index: job.kind == .video ? 1 : item.idx,
            title: item.title,
            duration: item.duration,
            thumbnail: item.thumbnail
        )
    }

    private func createJob(api: APIClient, entries: [JobItemInput]) async throws {
        _ = try await api.createJob(
            JobCreateRequest(
                url: job.url,
                kind: job.kind,
                playlistId: nil,
                playlistTitle: job.playlistTitle,
                entries: entries
            )
        )
    }
}
