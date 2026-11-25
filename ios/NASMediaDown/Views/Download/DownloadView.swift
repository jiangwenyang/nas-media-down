import SwiftUI
import UIKit

/// 下载页：粘贴网址、探测视频或播放列表、创建任务。
struct DownloadView: View {
    @Environment(AppState.self) private var app

    @State private var urlText = ""
    @State private var probing = false
    @State private var result: ProbeResult?
    @State private var probeError: String?
    @State private var creating = false
    @State private var showPlaylist = false

    @FocusState private var urlFocused: Bool

    private var activeJobs: [Job] {
        Array(app.jobs.activeJobs.prefix(4))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    composer

                    if let probeError {
                        ErrorNotice(text: probeError)
                    }

                    if probing {
                        ProbeSkeleton()
                    } else if let result {
                        resultSection(result)
                    }

                    if !activeJobs.isEmpty {
                        activeSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.large)
            .onAppear(perform: consumeSharedLink)
            .onChange(of: app.pendingProbeURL) { _, _ in
                consumeSharedLink()
            }
            .onChange(of: probing) { _, active in
                if !active { consumeSharedLink() }
            }
            .sheet(isPresented: $showPlaylist) {
                if let playlist = result?.playlist {
                    PlaylistPickerView(
                        playlist: playlist,
                        currentVideo: result?.video
                    ) { selection in
                        try await createJob(from: selection)
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    // MARK: - 区块

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("粘贴网址，")
                + Text("剩下的交给 NAS").foregroundStyle(Theme.brandGradient))
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("自动识别视频与关联播放列表，勾选后按最佳画质下载到映射目录。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("粘贴网址或 B 站分享文本…", text: $urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($urlFocused)
                    .onSubmit(probe)

                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                        result = nil
                        probeError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空网址")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                Theme.muted,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )

            HStack(spacing: 10) {
                Button(action: pasteFromClipboard) {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
                .secondaryAction()
                .disabled(probing)

                Spacer()

                Button(action: probe) {
                    HStack(spacing: 6) {
                        if probing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.onInk)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(probing ? "探测中…" : "探测")
                    }
                    .frame(minWidth: 82)
                }
                .primaryAction()
                .disabled(probing)
            }

            Text("支持粘贴 B 站分享文本（含 b23.tv 短链）、YouTube 等站点链接，也可直接粘贴 m3u8；播放列表会弹出选择。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardSurface()
    }

    @ViewBuilder
    private func resultSection(_ result: ProbeResult) -> some View {
        switch result.kind {
        case .video:
            if let video = result.video {
                videoCard(video)
            }
        case .playlist:
            if let playlist = result.playlist {
                playlistCard(playlist)
            }
        case .unknown:
            EmptyView()
        }
    }

    private func videoCard(_ video: VideoInfo) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(urlString: video.thumbnail)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipped()
                DurationBadge(seconds: video.duration)
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("单视频", systemImage: "film")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)

                Text(video.title)
                    .font(.headline)
                    .lineLimit(2)

                Label(video.uploader ?? "未知作者", systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    createSingleVideo(video)
                } label: {
                    HStack(spacing: 6) {
                        if creating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.onInk)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(creating ? "正在创建任务…" : "下载此视频")
                    }
                }
                .primaryAction()
                .disabled(creating)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .cardSurface(padded: false)
    }

    private func playlistCard(_ playlist: PlaylistInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: "list.and.film", tint: .secondary, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("播放列表 · \(playlist.count) 个视频")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(playlist.title)
                        .font(.headline)
                        .lineLimit(2)
                    if let current = result?.video {
                        Text("当前视频：\(current.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if let video = result?.video {
                    Button {
                        createSingleVideo(video)
                    } label: {
                        Text("仅当前视频")
                    }
                    .secondaryAction()
                    .disabled(creating)
                }

                Button {
                    showPlaylist = true
                } label: {
                    Label("选择下载", systemImage: "checklist")
                }
                .primaryAction()
                .disabled(creating)
            }
        }
        .cardSurface()
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("进行中的任务")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("查看全部") {
                    app.selectedTab = .jobs
                }
                .font(.caption)
            }

            ForEach(activeJobs) { job in
                JobRowView(job: job, compact: true)
                    .cardSurface()
            }
        }
    }

    // MARK: - 动作

    /// 接收分享扩展传入的链接并立即探测。
    private func consumeSharedLink() {
        guard !probing, let link = app.consumePendingProbeURL() else { return }
        urlText = link
        result = nil
        probeError = nil
        probe()
    }

    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            urlText = text
            result = nil
            probeError = nil
        } else {
            app.showToast("剪贴板中没有可用的网址", style: .info)
        }
        urlFocused = true
    }

    private func probe() {
        let value = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            app.showToast("请先粘贴视频网址", style: .info)
            return
        }
        guard !probing else { return }

        probing = true
        probeError = nil
        result = nil
        urlFocused = false

        Task {
            do {
                let api = try app.requireAPI()
                let data = try await api.probe(url: value)
                result = data
                if data.kind == .playlist {
                    showPlaylist = true
                }
            } catch {
                probeError = APIError.describe(error)
            }
            probing = false
        }
    }

    private func createSingleVideo(_ video: VideoInfo) {
        guard !creating else { return }
        creating = true
        Task {
            do {
                try await createJob(
                    kind: .video,
                    entries: [
                        JobItemInput(
                            index: 1,
                            title: video.title,
                            duration: video.duration,
                            thumbnail: video.thumbnail
                        )
                    ]
                )
            } catch {
                app.showToast(APIError.describe(error), style: .error)
            }
            creating = false
        }
    }

    private func createJob(from selection: PlaylistSelection) async throws {
        guard let playlist = result?.playlist else { return }
        if selection.mode == .current, let video = result?.video {
            try await createJob(
                kind: .video,
                entries: [
                    JobItemInput(
                        index: 1,
                        title: video.title,
                        duration: video.duration,
                        thumbnail: video.thumbnail
                    )
                ]
            )
            return
        }
        try await createJob(
            kind: .playlist,
            playlist: playlist,
            entries: selection.entries.map {
                JobItemInput(
                    index: $0.index,
                    title: $0.title,
                    duration: $0.duration,
                    thumbnail: $0.thumbnail
                )
            }
        )
    }

    private func createJob(kind: MediaKind, playlist: PlaylistInfo? = nil, entries: [JobItemInput]) async throws {
        let api = try app.requireAPI()
        let response = try await api.createJob(
            JobCreateRequest(
                url: urlText.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind,
                playlistId: playlist?.id,
                playlistTitle: playlist?.title,
                entries: entries
            )
        )
        app.showToast("已加入下载队列，共 \(response.itemCount) 个视频", style: .success)
        await app.jobs.refresh()
    }
}

/// 探测过程中的骨架占位。
private struct ProbeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 150)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 180, height: 14)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .frame(width: 110, height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .overlay {
            ProgressView()
                .controlSize(.regular)
        }
    }
}
