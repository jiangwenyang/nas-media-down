import SwiftUI

/// 追番 / 追剧：关注列表、追更订阅与选集下载。
struct BangumiView: View {
    @Environment(AppState.self) private var app

    @State private var loginChecked = false
    @State private var loggedIn = false

    @State private var mediaType = 1
    @State private var items: [BangumiFollowItem] = []
    @State private var page = 1
    @State private var total = 0
    @State private var hasMore = false
    @State private var loadingFollow = false
    @State private var followError: String?

    @State private var subscriptions: [BangumiSubscription] = []
    @State private var loadingSubs = false
    @State private var subsError: String?

    @State private var busy: String?
    @State private var episodeTarget: SeasonTarget?
    @State private var confirmTarget: BangumiSubscription?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if !loginChecked {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 92)
                        } else {
                            loginPrompt
                            subscriptionsSection(proxy: proxy)
                            if loggedIn {
                                followSection(proxy: proxy)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
            .appBackground()
            .navigationTitle("追番 · 追剧")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadStatus()
                await loadSubscriptions()
                if loggedIn { await loadFollow(reset: true) }
            }
            .task { await initialize() }
            .onChange(of: mediaType) { _, _ in
                guard loggedIn else { return }
                Task { await loadFollow(reset: true) }
            }
            .sheet(item: $episodeTarget) { target in
                EpisodePickerView(
                    seasonId: target.id,
                    title: target.title,
                    subscribed: target.subscribed
                ) { indices in
                    try await downloadSelected(seasonId: target.id, indices: indices)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "取消追更",
                isPresented: Binding(
                    get: { confirmTarget != nil },
                    set: { if !$0 { confirmTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("取消追更", role: .destructive) {
                    if let target = confirmTarget {
                        unsubscribe(target)
                    }
                    confirmTarget = nil
                }
                Button("保留", role: .cancel) { confirmTarget = nil }
            } message: {
                Text("将停止跟踪《\(confirmTarget?.title ?? "")》的更新，已下载的文件不会被删除。")
            }
        }
    }

    // MARK: - 页面区块

    private var header: some View {
        Text("读取哔哩哔哩关注列表，选择追更；有新剧集发布时自动下载，也可直接下载整季。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    @ViewBuilder
    private var loginPrompt: some View {
        if !loggedIn {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: "tv", tint: Theme.accent, size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text("需要先登录哔哩哔哩")
                        .font(.subheadline.weight(.semibold))
                    Text("关注列表需要账号登录才能读取。已订阅的剧集仍会显示在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("去账号页登录") {
                        app.selectedTab = .account
                    }
                    .inlineAction()
                    .padding(.top, 2)
                }
            }
            .cardSurface()
        }
    }

    private func subscriptionsSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(
                    title: "正在追更",
                    subtitle: subscriptions.isEmpty ? nil : "共 \(subscriptions.count) 部"
                )
                Spacer()
                Button {
                    Task { await loadSubscriptions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(loadingSubs)
                .accessibilityLabel("刷新追更")
            }

            if let subsError {
                ErrorNotice(text: subsError)
            }

            if loadingSubs && subscriptions.isEmpty {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 132)
                }
            } else if subscriptions.isEmpty {
                EmptyStateCard(
                    icon: "bell.badge",
                    title: "还没有追更的剧集",
                    message: loggedIn
                        ? "在下方关注列表里点「追更」，有新集时自动下载。"
                        : "登录哔哩哔哩后可浏览关注列表并选择追番。"
                )
            } else {
                ForEach(subscriptions) { subscription in
                    subscriptionCard(subscription, proxy: proxy)
                        .id("sub-\(subscription.id)")
                }
            }
        }
    }

    private func followSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "我的关注", subtitle: "共 \(total) 部")
                Spacer()
                Picker("类型", selection: $mediaType) {
                    Text("番剧").tag(1)
                    Text("追剧").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 148)
            }

            if let followError {
                ErrorNotice(text: followError)
            }

            if loadingFollow && items.isEmpty {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .frame(height: 260)
                    }
                }
            } else if items.isEmpty && followError == nil {
                EmptyStateCard(
                    icon: "rectangle.stack.badge.person.crop",
                    title: mediaType == 1 ? "没有追番记录" : "没有追剧记录",
                    message: "在哔哩哔哩 App 中关注后即可在这里看到。"
                )
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        posterCard(item, proxy: proxy)
                    }
                }
            }

            if hasMore {
                HStack {
                    Spacer()
                    Button {
                        Task { await loadFollow(reset: false) }
                    } label: {
                        if loadingFollow {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("加载更多")
                        }
                    }
                    .secondaryAction()
                    .disabled(loadingFollow)
                    Spacer()
                }
            }
        }
    }

    private func subscriptionCard(_ sub: BangumiSubscription, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(urlString: sub.cover, symbol: "sparkles.tv")
                    .frame(width: 58, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(sub.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Menu {
                            Button {
                                downloadAll(sub)
                            } label: {
                                Label("下载全部剧集", systemImage: "arrow.down.to.line")
                            }
                            Button {
                                toggleAuto(sub)
                            } label: {
                                Label(
                                    sub.autoDownload ? "关闭自动下载" : "开启自动下载",
                                    systemImage: sub.autoDownload ? "bell.slash" : "bell"
                                )
                            }
                            Button {
                                openEpisodes(sub.seasonId, title: sub.title, subscribed: true)
                            } label: {
                                Label("选集下载", systemImage: "checklist")
                            }
                            Divider()
                            Button(role: .destructive) {
                                confirmTarget = sub
                            } label: {
                                Label("取消追更", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                        .disabled(busy != nil)
                    }

                    HStack(spacing: 6) {
                        StatusBadge(
                            text: sub.autoDownload ? "自动下载" : "仅手动",
                            tint: sub.autoDownload ? Theme.accent : .secondary
                        )
                        if sub.queuedCount > 0 {
                            StatusBadge(text: "\(sub.queuedCount) 集排队中", tint: Theme.accent)
                        }
                        if sub.failedCount > 0 {
                            StatusBadge(text: "\(sub.failedCount) 集失败", tint: Theme.danger)
                        }
                    }

                    Text(sub.latestTitle ?? "暂无剧集")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    ProgressTrack(progress: progress(sub), height: 5)

                    Text("已下载 \(sub.doneCount)/\(sub.episodeCount) 集 · 上次检查 \(sub.lastCheckAt == nil ? "尚未检查" : Format.date(sub.lastCheckAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if let lastError = sub.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(Theme.danger.opacity(0.85))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    checkNow(sub)
                } label: {
                    HStack(spacing: 4) {
                        if isBusy("check-\(sub.id)") {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("立即检查")
                    }
                }
                .inlineAction()
                .disabled(busy != nil)

                Button("选集下载") {
                    openEpisodes(sub.seasonId, title: sub.title, subscribed: true)
                }
                .inlineAction()
                .disabled(busy != nil)

                Button("下载全部") {
                    downloadAll(sub)
                }
                .inlineAction()
                .disabled(busy != nil)

                Spacer(minLength: 0)
            }
        }
        .cardSurface()
    }

    private func posterCard(_ item: BangumiFollowItem, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImage(urlString: item.cover, symbol: "sparkles.tv")
                    .aspectRatio(3.0 / 4.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    StatusBadge(
                        text: item.isFinish ? "已完结" : "连载中",
                        tint: item.isFinish ? .secondary : Theme.accent
                    )
                    if item.subscribed {
                        StatusBadge(text: "已追更", tint: Theme.success)
                    }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .frame(height: 36, alignment: .topLeading)

                Text(item.newEp?.title ?? item.seasonTitle ?? "暂无更新信息")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if item.totalCount > 0 {
                    Text("共 \(item.totalCount) 集")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("集数未知")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 6) {
                    Button {
                        openEpisodes(item.seasonId, title: item.title, subscribed: item.subscribed)
                    } label: {
                        Text("选集下载")
                            .frame(maxWidth: .infinity)
                    }
                    .inlineAction()
                    .disabled(busy != nil)

                    if item.subscribed {
                        Button("查看进度") {
                            if let id = item.subscriptionId {
                                withAnimation(.smooth) {
                                    proxy.scrollTo("sub-\(id)", anchor: .center)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 6) {
                            Button {
                                subscribe(item, mode: "watch")
                            } label: {
                                Text(isBusy("watch-\(item.seasonId)") ? "处理中…" : "追更")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                            }
                            .microAction()
                            .disabled(busy != nil)

                            Button {
                                subscribe(item, mode: "all")
                            } label: {
                                Text(isBusy("all-\(item.seasonId)") ? "加入中…" : "下载全集")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                            }
                            .microAction()
                            .disabled(busy != nil)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(10)
        }
        .cardSurface(padded: false)
    }

    // MARK: - 状态与动作

    private func isBusy(_ key: String) -> Bool {
        busy == key
    }

    private func progress(_ sub: BangumiSubscription) -> Double {
        guard sub.episodeCount > 0 else { return 0 }
        return min(1, Double(sub.doneCount) / Double(sub.episodeCount))
    }

    private func initialize() async {
        await loadStatus()
        await loadSubscriptions()
        if loggedIn {
            await loadFollow(reset: true)
        }
    }

    private func loadStatus() async {
        do {
            let api = try app.requireAPI()
            let status = try await api.bilibiliStatus()
            loggedIn = status.loggedIn
        } catch {
            loggedIn = false
        }
        loginChecked = true
    }

    private func loadSubscriptions() async {
        guard !loadingSubs else { return }
        loadingSubs = true
        subsError = nil
        defer { loadingSubs = false }
        do {
            let api = try app.requireAPI()
            subscriptions = try await api.bangumiSubscriptions()
        } catch {
            subsError = APIError.describe(error)
        }
    }

    private func loadFollow(reset: Bool) async {
        guard loggedIn, !loadingFollow else { return }
        loadingFollow = true
        followError = nil
        defer { loadingFollow = false }

        let targetPage = reset ? 1 : page + 1
        do {
            let api = try app.requireAPI()
            let data = try await api.bangumiFollow(mediaType: mediaType, page: targetPage)
            items = reset ? data.items : items + data.items
            page = data.page
            total = data.total
            hasMore = data.hasMore
        } catch {
            followError = APIError.describe(error)
        }
    }

    private func subscribe(_ item: BangumiFollowItem, mode: String) {
        let key = "\(mode)-\(item.seasonId)"
        guard busy == nil else { return }
        busy = key
        Task {
            do {
                let api = try app.requireAPI()
                let result = try await api.bangumiSubscribe(
                    seasonId: item.seasonId,
                    mediaType: mediaType,
                    mode: mode
                )
                if let index = items.firstIndex(where: { $0.seasonId == item.seasonId }) {
                    items[index].subscribed = true
                    items[index].subscriptionId = result.subscription?.id
                }
                if mode == "all" {
                    if result.jobCount > 0 {
                        app.showToast("已加入下载队列：\(result.jobCount) 个任务", style: .success)
                    } else if let error = result.error {
                        app.showToast(error, style: .error)
                    } else {
                        app.showToast("没有可下载的剧集", style: .info)
                    }
                } else {
                    app.showToast("已开始追更《\(item.title)》", style: .success)
                }
                await loadSubscriptions()
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            busy = nil
        }
    }

    private func openEpisodes(_ seasonId: Int, title: String, subscribed: Bool) {
        guard busy == nil else { return }
        episodeTarget = SeasonTarget(id: seasonId, title: title, subscribed: subscribed)
    }

    private func downloadSelected(seasonId: Int, indices: [Int]) async throws {
        let api = try app.requireAPI()
        let result = try await api.bangumiDownloadEpisodes(seasonId: seasonId, indices: indices)
        if result.jobCount > 0 {
            let skipped = result.skippedCount ?? 0
            let message = skipped > 0
                ? "已加入下载队列：\(result.episodeCount) 集，跳过 \(skipped) 集已下载"
                : "已加入下载队列：\(result.episodeCount) 集"
            app.showToast(message, style: .success)
        } else if let error = result.error {
            throw APIError(status: 0, message: error)
        } else {
            throw APIError(status: 0, message: "没有可下载的剧集")
        }
        await loadSubscriptions()
    }

    private func checkNow(_ sub: BangumiSubscription) {
        guard busy == nil else { return }
        busy = "check-\(sub.id)"
        Task {
            do {
                let api = try app.requireAPI()
                let result = try await api.bangumiCheckSubscription(id: sub.id)
                if result.busy == true {
                    app.showToast("正在检查中，请稍后再试", style: .info)
                } else if let error = result.error {
                    app.showToast(error, style: .error)
                } else if result.jobCount > 0 {
                    app.showToast("发现 \(result.newEpisodes) 集更新，已加入下载队列", style: .success)
                } else if result.newEpisodes > 0 {
                    app.showToast("发现 \(result.newEpisodes) 集更新", style: .info)
                } else {
                    app.showToast("暂无更新", style: .info)
                }
                await loadSubscriptions()
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            busy = nil
        }
    }

    private func downloadAll(_ sub: BangumiSubscription) {
        guard busy == nil else { return }
        busy = "all-\(sub.id)"
        Task {
            do {
                let api = try app.requireAPI()
                let result = try await api.bangumiDownloadAll(id: sub.id)
                if result.jobCount > 0 {
                    app.showToast("已加入 \(result.jobCount) 个下载任务，共 \(result.episodeCount) 集", style: .success)
                } else if let error = result.error {
                    app.showToast(error, style: .error)
                } else {
                    app.showToast("没有需要下载的剧集", style: .info)
                }
                await loadSubscriptions()
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            busy = nil
        }
    }

    private func toggleAuto(_ sub: BangumiSubscription) {
        guard busy == nil else { return }
        busy = "auto-\(sub.id)"
        Task {
            do {
                let api = try app.requireAPI()
                let updated = try await api.bangumiUpdateSubscription(
                    id: sub.id,
                    enabled: nil,
                    autoDownload: !sub.autoDownload
                )
                if let index = subscriptions.firstIndex(where: { $0.id == sub.id }) {
                    subscriptions[index] = updated
                }
                app.showToast(updated.autoDownload ? "已开启自动下载新集" : "已关闭自动下载", style: .info)
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            busy = nil
        }
    }

    private func unsubscribe(_ sub: BangumiSubscription) {
        guard busy == nil else { return }
        busy = "del-\(sub.id)"
        Task {
            do {
                let api = try app.requireAPI()
                try await api.bangumiDeleteSubscription(id: sub.id)
                if let index = items.firstIndex(where: { $0.seasonId == sub.seasonId }) {
                    items[index].subscribed = false
                    items[index].subscriptionId = nil
                }
                app.showToast("已取消追更", style: .success)
                await loadSubscriptions()
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            busy = nil
        }
    }
}

/// 选集目标。
struct SeasonTarget: Identifiable {
    let id: Int
    let title: String
    let subscribed: Bool
}
