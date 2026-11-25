import Foundation

/// 应用自定义 URL Scheme 的解析与校验。
enum DeepLink {
    static let scheme = "nasmediadown"

    /// 解析 `nasmediadown://probe?url=<编码后的链接>`，返回待探测的网页链接。
    /// - Parameter url: 外部应用或分享扩展打开的深链接。
    /// - Returns: 合法时返回原始网页链接，否则返回 `nil`。
    static func probeLink(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == "probe",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            return nil
        }

        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: link),
              let parsedScheme = parsed.scheme?.lowercased(),
              parsedScheme == "http" || parsedScheme == "https" else {
            return nil
        }
        return link
    }
}
