import Foundation
import Observation

/// 任务列表轮询：有活动任务时每秒刷新，空闲时每 10 秒刷新。
@MainActor
@Observable
final class JobsStore {
    private(set) var jobs: [Job] = []
    private(set) var loading = false
    private(set) var error: String?

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    var activeJobs: [Job] {
        jobs.filter { $0.status.isActive }
    }

    /// 开始轮询；同一时间只保留一个轮询任务。
    func start(api: APIClient) {
        self.api = api
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                guard let self else { return }
                let delay: UInt64 = self.activeJobs.isEmpty ? 10 : 1
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                if Task.isCancelled { return }
                await self.refresh()
            }
        }
    }

    /// 停止轮询。
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        api = nil
    }

    /// 立即拉取一次任务列表。
    func refresh() async {
        guard let api else { return }
        loading = true
        defer { loading = false }
        do {
            jobs = try await api.listJobs()
            error = nil
        } catch {
            let message = APIError.describe(error)
            if message != "请求已取消" {
                self.error = message
            }
        }
    }
}
