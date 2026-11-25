import SwiftUI

/// 任务中心：统计概览、带计数的筛选与可操作的任务卡片。
struct JobsView: View {
    @Environment(AppState.self) private var app
    @State private var filter: JobFilter = .all

    private var allJobs: [Job] { app.jobs.jobs }
    private var activeJobs: [Job] { allJobs.filter { $0.status.isActive } }
    private var doneJobs: [Job] {
        allJobs.filter { job in
            job.status == .completed || job.status == .partial
        }
    }
    private var failedJobs: [Job] {
        let statuses: [JobStatus] = [.failed, .cancelled, .interrupted, .unknown]
        return allJobs.filter { job in
            statuses.contains(job.status)
        }
    }

    private var activeSpeed: Double {
        var total: Double = 0
        for job in activeJobs {
            for item in job.items ?? [] where item.status == .downloading {
                total += item.speed ?? 0
            }
        }
        return total
    }

    private var filtered: [Job] {
        switch filter {
        case .all: return allJobs
        case .active: return activeJobs
        case .done: return doneJobs
        case .failed: return failedJobs
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !allJobs.isEmpty {
                    summaryBar
                    filterBar
                    Divider()
                        .opacity(0.4)
                }

                list
            }
            .appBackground()
            .navigationTitle("任务")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await app.jobs.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新任务")
                }
            }
        }
    }

    // MARK: - 概览与筛选

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryStat(
                value: activeJobs.count,
                label: "进行中",
                tint: Theme.ink,
                symbol: "arrow.down.circle.fill",
                detail: Format.speed(activeSpeed)
            )
            summaryDivider
            summaryStat(
                value: doneJobs.count,
                label: "已完成",
                tint: .secondary,
                symbol: "checkmark.circle.fill"
            )
            summaryDivider
            summaryStat(
                value: failedJobs.count,
                label: "失败",
                tint: .secondary,
                symbol: "exclamationmark.circle.fill"
            )
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private func summaryStat(
        value: Int,
        label: String,
        tint: Color,
        symbol: String,
        detail: String? = nil
    ) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text("\(value)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                if let detail {
                    Text(detail)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 30)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(JobFilter.allCases) { item in
                    filterChip(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func filterChip(_ item: JobFilter) -> some View {
        let selected = filter == item
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                filter = item
            }
        } label: {
            HStack(spacing: 6) {
                Text(item.label)
                Text("\(count(for: item))")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(selected ? Theme.onInk.opacity(0.75) : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        selected ? Theme.onInk.opacity(0.15) : Color.primary.opacity(0.06),
                        in: Capsule()
                    )
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? Theme.onInk : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule().fill(Theme.ink)
                } else {
                    Capsule()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(Capsule().strokeBorder(Theme.hairline))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func count(for item: JobFilter) -> Int {
        switch item {
        case .all: return allJobs.count
        case .active: return activeJobs.count
        case .done: return doneJobs.count
        case .failed: return failedJobs.count
        }
    }

    // MARK: - 列表

    private var list: some View {
        List {
            if let error = app.jobs.error {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ErrorNotice(text: error)
                        Button("重新加载") {
                            Task { await app.jobs.refresh() }
                        }
                        .inlineAction()
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if app.jobs.loading && allJobs.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    JobSkeletonCard()
                        .cardSurface()
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else if filtered.isEmpty {
                if app.jobs.error == nil {
                    EmptyStateCard(
                        icon: "tray",
                        title: filter.emptyTitle,
                        message: filter.emptyMessage
                    )
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(filtered) { job in
                    JobRowView(job: job)
                        .cardSurface()
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await app.jobs.refresh() }
    }
}

/// 任务筛选条件。
enum JobFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case done
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .active: return "进行中"
        case .done: return "已完成"
        case .failed: return "失败"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "还没有下载任务"
        case .active: return "没有进行中的下载"
        case .done: return "还没有已完成的任务"
        case .failed: return "没有失败或中断的任务"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "回到「下载」页粘贴网址即可创建任务"
        case .active: return "新的下载会实时显示在这里"
        case .done: return "完成的任务会保留在这里"
        case .failed: return "失败的任务可以单独重试"
        }
    }
}

/// 首次加载时的骨架卡片。
private struct JobSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 180, height: 13)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 110, height: 10)
                }
            }
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(height: 8)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .frame(width: 80, height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
