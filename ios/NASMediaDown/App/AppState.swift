import Foundation
import Observation
import UIKit

/// 应用底部标签页。
enum AppTab: String, CaseIterable, Identifiable {
    case download
    case bangumi
    case jobs
    case files
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: return "下载"
        case .bangumi: return "追番"
        case .jobs: return "任务"
        case .files: return "文件"
        case .account: return "账号"
        }
    }

    var systemImage: String {
        switch self {
        case .download: return "arrow.down.circle"
        case .bangumi: return "sparkles.tv"
        case .jobs: return "list.bullet.rectangle"
        case .files: return "folder"
        case .account: return "person.crop.circle"
        }
    }
}

/// 轻提示。
struct ToastMessage: Identifiable, Equatable {
    enum Style {
        case success
        case error
        case info
    }

    let id = UUID()
    let text: String
    let style: Style
}

/// 全局状态：服务器列表、连接、登录态与轻提示。
@MainActor
@Observable
final class AppState {
    enum Route: Equatable {
        case launch
        case servers
        case login
        case main
    }

    private(set) var route: Route = .launch
    private(set) var servers: [Server] = []
    private(set) var selectedServerID: UUID?
    private(set) var currentVersion: String?
    private(set) var api: APIClient?
    private(set) var toast: ToastMessage?

    var selectedTab: AppTab = .download

    let jobs = JobsStore()

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var didStart = false

    private enum Keys {
        static let servers = "nas.media.servers.v1"
        static let selected = "nas.media.selectedServer.v1"
    }

    init() {
        loadPersistedServers()
    }

    var selectedServer: Server? {
        guard let selectedServerID else { return nil }
        return servers.first { $0.id == selectedServerID }
    }

    /// 获取当前客户端，未连接时抛出可展示的错误。
    func requireAPI() throws -> APIClient {
        guard let api else { throw APIError.notConnected }
        return api
    }

    /// 应用启动时恢复上次选择的服务器。
    func start() async {
        guard !didStart else { return }
        didStart = true
        guard let server = selectedServer else {
            route = .servers
            return
        }
        await connect(server)
    }

    // MARK: - 服务器

    /// 选择并连接服务器。
    func select(_ server: Server) async {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].lastUsedAt = Date()
            persist()
        }
        await connect(server)
    }

    /// 校验地址后保存服务器并立即连接。
    @discardableResult
    func addServer(name: String, address: String) async throws -> Server {
        guard let url = ServerAddress.normalize(address) else {
            throw APIError.invalidServer
        }

        let probeClient = APIClient(baseURL: url)
        _ = try await probeClient.health()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var server: Server
        if let index = servers.firstIndex(where: { $0.urlString == url.absoluteString }) {
            server = servers[index]
            if !trimmedName.isEmpty { server.name = trimmedName }
            server.lastUsedAt = Date()
            servers[index] = server
        } else {
            server = Server(
                name: trimmedName.isEmpty ? ServerAddress.defaultName(for: url) : trimmedName,
                urlString: url.absoluteString,
                lastUsedAt: Date()
            )
            servers.append(server)
        }
        persist()
        await connect(server)
        return server
    }

    /// 删除保存的服务器。
    func deleteServer(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        if selectedServerID == server.id {
            selectedServerID = nil
            api = nil
            jobs.stop()
            route = .servers
        }
        persist()
    }

    // MARK: - 登录

    func login(password: String) async throws {
        let client = try requireAPI()
        try await client.login(password: password)
        jobs.start(api: client)
        route = .main
    }

    func logout() async {
        jobs.stop()
        try? await api?.logout()
        if let url = selectedServer?.baseURL {
            clearCookies(for: url)
        }
        route = .login
    }

    /// 回到服务器列表而不退出登录态。
    func switchServer() {
        jobs.stop()
        api = nil
        route = .servers
    }

    // MARK: - 轻提示

    func showToast(_ text: String, style: ToastMessage.Style = .info) {
        let message = ToastMessage(text: text, style: style)
        toastTask?.cancel()
        toast = message

        switch style {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .info:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == message.id {
                self?.toast = nil
            }
        }
    }

    // MARK: - 内部逻辑

    private func connect(_ server: Server) async {
        guard let url = server.baseURL else {
            route = .servers
            showToast("服务器地址无效", style: .error)
            return
        }

        route = .launch
        selectedServerID = server.id
        persist()

        let client = APIClient(baseURL: url)
        client.onUnauthorized = { [weak self] in
            Task { @MainActor in
                self?.handleSessionExpired()
            }
        }
        api = client

        do {
            let health = try await client.health()
            currentVersion = health.version
            let session = try await client.me()
            if session.authenticated {
                jobs.start(api: client)
                route = .main
            } else {
                jobs.stop()
                route = .login
            }
        } catch {
            api = nil
            currentVersion = nil
            route = .servers
            showToast(APIError.describe(error), style: .error)
        }
    }

    private func handleSessionExpired() {
        guard route == .main else { return }
        jobs.stop()
        route = .login
        showToast("登录已过期，请重新登录", style: .info)
    }

    private func clearCookies(for url: URL) {
        let storage = HTTPCookieStorage.shared
        storage.cookies(for: url)?.forEach { storage.deleteCookie($0) }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: Keys.servers)
        }
        defaults.set(selectedServerID?.uuidString, forKey: Keys.selected)
    }

    private func loadPersistedServers() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.servers),
           let saved = try? JSONDecoder().decode([Server].self, from: data) {
            servers = saved
        }
        if let raw = defaults.string(forKey: Keys.selected),
           let id = UUID(uuidString: raw),
           servers.contains(where: { $0.id == id }) {
            selectedServerID = id
        }
    }
}
