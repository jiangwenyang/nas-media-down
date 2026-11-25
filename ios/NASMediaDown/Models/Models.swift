import Foundation

// MARK: - 服务器

/// 用户保存的 NAS 服务器。
struct Server: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var urlString: String
    var addedAt: Date
    var lastUsedAt: Date?

    init(id: UUID = UUID(), name: String, urlString: String, addedAt: Date = Date(), lastUsedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt
    }

    var baseURL: URL? { URL(string: urlString) }

    var address: String {
        guard let url = baseURL else { return urlString }
        var text = url.host ?? urlString
        if let port = url.port { text += ":\(port)" }
        if url.path.count > 1 { text += url.path }
        return text
    }
}

/// 服务器地址的规范化与展示。
enum ServerAddress {
    /// 补全协议、移除末尾斜杠，返回可用的基础地址。
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty
        else { return nil }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// 没有填写名称时使用主机名生成一个可读的默认名称。
    static func defaultName(for url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        return "NAS · \(host)"
    }
}

// MARK: - 基础响应

struct HealthResponse: Codable {
    let status: String
    let version: String?
}

struct AuthState: Codable {
    let authenticated: Bool
}

struct OkResponse: Codable {
    let ok: Bool
}

// MARK: - 探测

enum ProbeKind: String, Codable {
    case video
    case playlist
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProbeKind(rawValue: raw) ?? .unknown
    }
}

struct VideoInfo: Codable, Hashable {
    let id: String?
    let title: String
    let duration: Double?
    let thumbnail: String?
    let uploader: String?
    let webpageUrl: String?
}

struct PlaylistEntry: Codable, Identifiable, Hashable {
    let index: Int
    let title: String
    let duration: Double?
    let thumbnail: String?

    var id: Int { index }
}

struct PlaylistInfo: Codable, Hashable {
    let id: String?
    let title: String
    let count: Int
    let truncated: Bool
    let entries: [PlaylistEntry]
}

struct ProbeResult: Codable {
    let kind: ProbeKind
    let video: VideoInfo?
    let playlist: PlaylistInfo?
}

// MARK: - 任务

enum MediaKind: String, Codable {
    case video
    case playlist
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaKind(rawValue: raw) ?? .unknown
    }
}

enum JobStatus: String, Codable {
    case queued
    case running
    case partial
    case completed
    case failed
    case cancelled
    case interrupted
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = JobStatus(rawValue: raw) ?? .unknown
    }

    var isActive: Bool { self == .queued || self == .running }
    var canRetry: Bool { [.failed, .cancelled, .interrupted, .partial].contains(self) }
}

enum ItemStatus: String, Codable {
    case pending
    case downloading
    case processing
    case done
    case failed
    case cancelled
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemStatus(rawValue: raw) ?? .unknown
    }
}

struct JobItem: Codable, Identifiable, Hashable {
    let idx: Int
    let title: String
    let thumbnail: String?
    let duration: Double?
    let status: ItemStatus
    let progress: Double
    let downloadedBytes: Double?
    let totalBytes: Double?
    let speed: Double?
    let eta: Double?
    let filename: String?
    let error: String?

    var id: Int { idx }
}

struct Job: Codable, Identifiable, Hashable {
    let id: String
    let url: String
    let kind: MediaKind
    let title: String
    let playlistTitle: String?
    let status: JobStatus
    let progress: Double
    let error: String?
    let createdAt: Double
    let startedAt: Double?
    let finishedAt: Double?
    let itemCount: Int
    let items: [JobItem]?
}

struct JobDetail: Codable {
    let job: Job
    let items: [JobItem]
}

struct JobsEnvelope: Codable {
    let jobs: [Job]
}

struct CreateJobResponse: Codable {
    let jobId: String
    let itemCount: Int
}

struct JobItemInput: Encodable {
    let index: Int
    let title: String
    let duration: Double?
    let thumbnail: String?
}

struct JobCreateRequest: Encodable {
    let url: String
    let kind: MediaKind
    let playlistId: String?
    let playlistTitle: String?
    let entries: [JobItemInput]
}

// MARK: - 文件

struct FileEntry: Codable, Identifiable, Hashable {
    let name: String
    let path: String
    let isDir: Bool
    let size: Int64
    let mtime: Double
    let mime: String?

    var id: String { path }

    var isPreviewable: Bool {
        let mime = mime ?? ""
        return mime.hasPrefix("video/")
            || mime.hasPrefix("audio/")
            || mime.hasPrefix("image/")
            || mime == "application/pdf"
    }
}

struct FileListing: Codable {
    let path: String
    let parent: String?
    let entries: [FileEntry]
}

/// 后端签发的短期文件链接。
struct ShareLink: Codable {
    let token: String
    let expiresAt: Double
}

// MARK: - 哔哩哔哩

struct BilibiliQRCode: Codable {
    let url: String
    let key: String
}

struct BilibiliPoll: Codable {
    let code: Int
    let status: String
    let loggedIn: Bool
    let uname: String?
    let vip: Bool
}

struct BilibiliStatus: Codable {
    let loggedIn: Bool
    let uname: String?
    let vip: Bool
    let expiresAt: Double?
}

// MARK: - 追番 / 追剧

struct BangumiNewEp: Codable, Hashable {
    let title: String?
    let pubTime: String?
}

struct BangumiFollowItem: Codable, Identifiable, Hashable {
    let seasonId: Int
    let mediaId: Int?
    let type: Int
    let title: String
    let cover: String?
    let seasonTitle: String?
    let totalCount: Int
    let isFinish: Bool
    let newEp: BangumiNewEp?
    let url: String
    var subscribed: Bool
    var subscriptionId: String?

    var id: Int { seasonId }
}

struct BangumiFollowPage: Codable {
    let items: [BangumiFollowItem]
    let page: Int
    let total: Int
    let hasMore: Bool
}

enum BangumiEpisodeStatus: String, Codable {
    case skipped
    case queued
    case done
    case failed
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BangumiEpisodeStatus(rawValue: raw) ?? .unknown
    }
}

struct BangumiSubscription: Codable, Identifiable, Hashable {
    let id: String
    let seasonId: Int
    let mediaId: Int?
    let type: Int
    let title: String
    let cover: String?
    let url: String
    var autoDownload: Bool
    let enabled: Bool
    let lastCheckAt: Double?
    let lastError: String?
    let createdAt: Double
    let episodeCount: Int
    let doneCount: Int
    let queuedCount: Int
    let failedCount: Int
    let skippedCount: Int
    let latestTitle: String?
    let latestStatus: BangumiEpisodeStatus?
}

struct BangumiSubscribeResult: Codable {
    let subscription: BangumiSubscription?
    let jobCount: Int
    let error: String?
}

struct BangumiCheckResult: Codable {
    let checked: Bool?
    let busy: Bool?
    let newEpisodes: Int
    let jobCount: Int
    let error: String?
}

struct BangumiDownloadResult: Codable {
    let episodeCount: Int
    let jobCount: Int
    let error: String?
    let subscription: BangumiSubscription?
}

struct BangumiSeasonEpisode: Codable, Identifiable, Hashable {
    let epId: Int
    let idx: Int
    let title: String
    let longTitle: String?
    let duration: Double?
    let cover: String?
    let pubTime: Double?
    let url: String
    let status: BangumiEpisodeStatus?

    var id: Int { idx }
}

struct BangumiSeasonDetail: Codable {
    let seasonId: Int
    let mediaId: Int?
    let title: String
    let seasonTitle: String?
    let cover: String?
    let totalCount: Int
    let episodes: [BangumiSeasonEpisode]
    let subscribed: Bool
}

struct SubscriptionEnvelope: Codable {
    let subscriptions: [BangumiSubscription]
}

struct BangumiSubscribeRequest: Encodable {
    let seasonId: Int
    let mediaType: Int
    let mode: String
}

struct BangumiUpdateRequest: Encodable {
    let enabled: Bool?
    let autoDownload: Bool?
}

struct BangumiDownloadRequest: Encodable {
    let seasonId: Int
    let episodeIndices: [Int]
}
