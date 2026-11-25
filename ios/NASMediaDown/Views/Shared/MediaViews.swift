import AVFoundation
import AVKit
import Observation
import SwiftUI
import UIKit

/// 系统分享面板，用于把下载到本地的文件存入「文件」App 或发送到其他应用。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 分享项包装，便于用 sheet(item:) 呈现。
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// 把服务器文件下载到本地临时目录。
enum FileDownloader {
    static func download(url: URL, filename: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 600

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "下载失败")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw APIError(status: 401, message: "登录状态已失效，请重新登录")
            }
            throw APIError(status: http.statusCode, message: "下载失败（\(http.statusCode)）")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASMediaDown", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safeName = filename
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let destination = directory.appendingPathComponent(safeName.isEmpty ? "download" : safeName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }
}

/// 用于 AVPlayer 的鉴权资源：把当前会话 Cookie 注入请求。
enum AuthorizedMedia {
    static func player(for url: URL) -> AVPlayer {
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
        return AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }
}

/// 视频播放页。
struct VideoPlayerScreen: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                ProgressView()
            }
        }
        .background(Color.black)
        .task {
            guard player == nil else { return }
            player = AuthorizedMedia.player(for: url)
        }
    }
}

/// 音频播放控制器。
@MainActor
@Observable
final class AudioPlayerModel {
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    func load(url: URL) {
        stop()
        let player = AuthorizedMedia.player(for: url)
        self.player = player

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.currentTime = 0
            self?.player?.seek(to: .zero)
        }

        Task { [weak self] in
            guard let item = player.currentItem,
                  let loaded = try? await item.asset.load(.duration) else { return }
            let seconds = loaded.seconds
            if seconds.isFinite {
                self?.duration = seconds
            }
        }
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        guard let player, seconds.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        currentTime = seconds
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
    }
}

/// 音频播放界面。
struct AudioPlayerScreen: View {
    let url: URL
    @State private var model = AudioPlayerModel()
    @State private var scrub: Double = 0
    @State private var scrubbing = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Theme.brandGradient)
                Image(systemName: "waveform")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(Theme.onInk)
            }
            .frame(width: 170, height: 170)
            .shadow(color: Theme.accent.opacity(0.3), radius: 24, y: 12)

            Text("音频播放")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Slider(
                    value: $scrub,
                    in: 0...max(model.duration, 0.1),
                    onEditingChanged: { editing in
                        scrubbing = editing
                        if !editing { model.seek(to: scrub) }
                    }
                )
                HStack {
                    Text(Format.duration(scrub))
                    Spacer()
                    Text(Format.duration(model.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Button {
                model.toggle()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 64, height: 64)
            }
            .circlePrimaryAction()
        }
        .padding(24)
        .task {
            model.load(url: url)
            scrub = 0
        }
        .onDisappear { model.stop() }
        .onChange(of: model.currentTime) { _, newValue in
            if !scrubbing { scrub = newValue }
        }
    }
}
