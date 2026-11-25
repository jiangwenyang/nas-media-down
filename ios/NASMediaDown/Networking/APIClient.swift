import Foundation

/// 与 NAS 后端通信的客户端，所有请求携带系统 Cookie 中的会话。
final class APIClient {
    /// 服务器根地址（可能带有反向代理路径前缀）。
    let baseURL: URL

    /// 受保护接口返回 401 时回调，用于回到登录页。
    var onUnauthorized: (() -> Void)?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL) {
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    // MARK: - 鉴权

    func health() async throws -> HealthResponse {
        try await send(request("GET", "/health", timeout: 12))
    }

    func me() async throws -> AuthState {
        try await send(request("GET", "/auth/me"))
    }

    func login(password: String) async throws {
        let request = try request("POST", "/auth/login", body: encode(LoginRequest(password: password)))
        _ = try await data(for: request, notifyUnauthorized: false)
    }

    func logout() async throws {
        let request = try request("POST", "/auth/logout")
        _ = try await data(for: request, notifyUnauthorized: false)
    }

    // MARK: - 探测与任务

    func probe(url: String) async throws -> ProbeResult {
        let request = try request("POST", "/probe", body: encode(ProbeRequest(url: url)), timeout: 300)
        return try await send(request)
    }

    func createJob(_ payload: JobCreateRequest) async throws -> CreateJobResponse {
        try await send(request("POST", "/jobs", body: encode(payload), timeout: 60))
    }

    func listJobs() async throws -> [Job] {
        let request = try request("GET", "/jobs", query: [URLQueryItem(name: "limit", value: "100")])
        return try await send(request, as: JobsEnvelope.self).jobs
    }

    func job(id: String) async throws -> JobDetail {
        try await send(request("GET", "/jobs/\(escape(id))"))
    }

    func cancelJob(id: String) async throws {
        _ = try await data(for: try request("POST", "/jobs/\(escape(id))/cancel"))
    }

    func deleteJob(id: String) async throws {
        _ = try await data(for: try request("DELETE", "/jobs/\(escape(id))"))
    }

    // MARK: - 文件

    func listFiles(path: String) async throws -> FileListing {
        try await send(request("GET", "/files", query: [URLQueryItem(name: "path", value: path)]))
    }

    func deleteFile(path: String, recursive: Bool) async throws {
        let request = try request("DELETE", "/files", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "recursive", value: recursive ? "1" : "0"),
        ])
        _ = try await data(for: request)
    }

    /// 文件内容地址；inline 为 true 时后端允许音视频与图片内联播放。
    func contentURL(path: String, inline: Bool) -> URL {
        url(for: "/files/content", query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "inline", value: inline ? "1" : "0"),
        ]) ?? baseURL
    }

    /// 为文件签发短期链接，供外部播放器直接访问。
    func createShareLink(path: String) async throws -> ShareLink {
        try await send(request("POST", "/files/share", body: encode(SharePathBody(path: path))))
    }

    /// 把分享 token 转换为完整地址。
    func shareURL(token: String) -> URL? {
        url(for: "/share/\(token)")
    }

    // MARK: - 哔哩哔哩

    func bilibiliQRCode() async throws -> BilibiliQRCode {
        try await send(request("POST", "/bilibili/qrcode"))
    }

    func bilibiliPoll(key: String) async throws -> BilibiliPoll {
        try await send(request("GET", "/bilibili/qrcode/poll", query: [URLQueryItem(name: "key", value: key)]))
    }

    func bilibiliStatus() async throws -> BilibiliStatus {
        try await send(request("GET", "/bilibili/status"))
    }

    func bilibiliLogout() async throws {
        _ = try await data(for: try request("POST", "/bilibili/logout"))
    }

    // MARK: - 追番 / 追剧

    func bangumiFollow(mediaType: Int, page: Int) async throws -> BangumiFollowPage {
        try await send(request("GET", "/bangumi/follow", query: [
            URLQueryItem(name: "type", value: String(mediaType)),
            URLQueryItem(name: "page", value: String(page)),
        ]))
    }

    func bangumiSeason(id: Int) async throws -> BangumiSeasonDetail {
        try await send(request("GET", "/bangumi/season/\(id)"))
    }

    func bangumiDownloadEpisodes(seasonId: Int, indices: [Int]) async throws -> BangumiDownloadResult {
        let body = BangumiDownloadRequest(seasonId: seasonId, episodeIndices: indices)
        return try await send(request("POST", "/bangumi/download", body: encode(body), timeout: 120))
    }

    func bangumiSubscriptions() async throws -> [BangumiSubscription] {
        try await send(request("GET", "/bangumi/subscriptions"), as: SubscriptionEnvelope.self).subscriptions
    }

    func bangumiSubscribe(seasonId: Int, mediaType: Int, mode: String) async throws -> BangumiSubscribeResult {
        let body = BangumiSubscribeRequest(seasonId: seasonId, mediaType: mediaType, mode: mode)
        return try await send(request("POST", "/bangumi/subscriptions", body: encode(body), timeout: 120))
    }

    func bangumiUpdateSubscription(id: String, enabled: Bool?, autoDownload: Bool?) async throws -> BangumiSubscription {
        let body = BangumiUpdateRequest(enabled: enabled, autoDownload: autoDownload)
        return try await send(request("PATCH", "/bangumi/subscriptions/\(escape(id))", body: encode(body)))
    }

    func bangumiDeleteSubscription(id: String) async throws {
        _ = try await data(for: try request("DELETE", "/bangumi/subscriptions/\(escape(id))"))
    }

    func bangumiCheckSubscription(id: String) async throws -> BangumiCheckResult {
        try await send(request("POST", "/bangumi/subscriptions/\(escape(id))/check", timeout: 120))
    }

    func bangumiDownloadAll(id: String) async throws -> BangumiDownloadResult {
        try await send(request("POST", "/bangumi/subscriptions/\(escape(id))/download-all", timeout: 120))
    }

    // MARK: - 请求构建与发送

    /// 拼接 /api 前缀并附加查询参数。
    func url(for path: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = components.path == "/" ? "" : components.path
        let suffix = path.hasPrefix("/") ? path : "/" + path
        components.path = basePath + "/api" + suffix
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }

    private func request(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) throws -> URLRequest {
        guard let url = url(for: path, query: query) else {
            throw APIError.invalidServer
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("NASMediaDown-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw APIError(status: 0, message: "请求数据编码失败")
        }
    }

    private func send<T: Decodable>(_ request: URLRequest, notifyUnauthorized: Bool = true) async throws -> T {
        try await send(request, as: T.self, notifyUnauthorized: notifyUnauthorized)
    }

    private func send<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type,
        notifyUnauthorized: Bool = true
    ) async throws -> T {
        let data = try await data(for: request, notifyUnauthorized: notifyUnauthorized)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError(status: 0, message: "服务器返回了无法解析的数据")
        }
    }

    @discardableResult
    private func data(for request: URLRequest, notifyUnauthorized: Bool = true) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "服务器响应无效")
        }
        if http.statusCode == 401, notifyUnauthorized {
            onUnauthorized?()
        }
        guard (200..<300).contains(http.statusCode) else {
            throw parseError(data: data, status: http.statusCode)
        }
        return data
    }

    private func parseError(data: Data, status: Int) -> APIError {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = object["detail"] {
            if let text = detail as? String {
                return APIError(status: status, message: text)
            }
            if let items = detail as? [[String: Any]] {
                let messages = items.compactMap { $0["msg"] as? String }
                if !messages.isEmpty {
                    return APIError(status: status, message: messages.joined(separator: "；"))
                }
            }
        }
        if status == 401 {
            return APIError(status: status, message: "登录状态已失效，请重新登录")
        }
        return APIError(status: status, message: "请求失败（\(status)）")
    }

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private struct LoginRequest: Encodable {
    let password: String
}

private struct ProbeRequest: Encodable {
    let url: String
}

private struct SharePathBody: Encodable {
    let path: String
}
