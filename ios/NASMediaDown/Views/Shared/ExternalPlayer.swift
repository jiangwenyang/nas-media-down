import SwiftUI
import UIKit

/// 外部播放器 URL Scheme 与打开动作。
@MainActor
enum ExternalPlayer {
    struct Option: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let url: URL
    }

    /// 返回已安装且声明了 URL Scheme 的播放器。
    static func options(for remoteURL: URL) -> [Option] {
        var result: [Option] = []

        if let url = schemeURL(base: "infuse://x-callback-url/play", remoteURL: remoteURL),
           UIApplication.shared.canOpenURL(url) {
            result.append(
                Option(
                    id: "infuse",
                    title: "Infuse",
                    subtitle: "在 Infuse 中直接播放",
                    systemImage: "play.rectangle.fill",
                    url: url
                )
            )
        }

        if let url = schemeURL(base: "vlc-x-callback://x-callback-url/stream", remoteURL: remoteURL),
           UIApplication.shared.canOpenURL(url) {
            result.append(
                Option(
                    id: "vlc",
                    title: "VLC",
                    subtitle: "在 VLC 中直接播放",
                    systemImage: "play.circle.fill",
                    url: url
                )
            )
        }

        return result
    }

    static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    private static func schemeURL(base: String, remoteURL: URL) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        return components.url
    }
}

/// 一次外部播放所需的远程链接。
struct PlaybackLink: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
    let expiresAt: Double
}
