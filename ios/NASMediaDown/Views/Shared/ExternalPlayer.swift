import Foundation
import UIKit

/// 在 VidHub 中打开远程文件。
@MainActor
enum ExternalPlayer {
    private static let baseURL = "open-vidhub://x-callback-url/open"

    static var isVidHubInstalled: Bool {
        guard let url = URL(string: baseURL) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func vidHubURL(for remoteURL: URL) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        return components.url
    }

    static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }
}
