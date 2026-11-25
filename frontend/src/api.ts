import type {
  BangumiCheckResult,
  BangumiDownloadAllResult,
  BangumiDownloadResult,
  BangumiFollowPage,
  BangumiSeasonDetail,
  BangumiSubscribeResult,
  BangumiSubscription,
  BilibiliPoll,
  BilibiliQrCode,
  BilibiliStatus,
  CreateJobPayload,
  FileListing,
  Job,
  JobDetail,
  ProbeResult,
  ShareLink,
} from './types'

export class ApiError extends Error {
  readonly status: number

  constructor(status: number, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  if (init.body) {
    headers.set('Content-Type', 'application/json')
  }

  const response = await fetch(`/api${path}`, {
    ...init,
    headers,
    credentials: 'include',
  })

  const text = await response.text()
  let data: unknown = null
  if (text) {
    try {
      data = JSON.parse(text)
    } catch {
      data = null
    }
  }

  if (!response.ok) {
    const detail = (data as { detail?: unknown } | null)?.detail
    let message = `请求失败（${response.status}）`
    if (typeof detail === 'string') {
      message = detail
    } else if (Array.isArray(detail)) {
      message = detail
        .map((item) => (item as { msg?: string })?.msg ?? '')
        .filter(Boolean)
        .join('；')
    }
    throw new ApiError(response.status, message)
  }

  return (data ?? undefined) as T
}

/** 把任意异常转成可展示文案。 */
export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) return error.message
  if (error instanceof Error) return error.message
  return '发生未知错误'
}

export const api = {
  me: () => request<{ authenticated: boolean }>('/auth/me'),
  login: (password: string) =>
    request<{ ok: boolean }>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ password }),
    }),
  logout: () => request<{ ok: boolean }>('/auth/logout', { method: 'POST' }),
  probe: (url: string) =>
    request<ProbeResult>('/probe', {
      method: 'POST',
      body: JSON.stringify({ url }),
    }),
  createJob: (payload: CreateJobPayload) =>
    request<{ job_id: string; item_count: number }>('/jobs', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
  listJobs: () => request<{ jobs: Job[] }>('/jobs?limit=100'),
  getJob: (id: string) => request<JobDetail>(`/jobs/${id}`),
  cancelJob: (id: string) =>
    request<{ ok: boolean }>(`/jobs/${id}/cancel`, { method: 'POST' }),
  deleteJob: (id: string) => request<void>(`/jobs/${id}`, { method: 'DELETE' }),
  listFiles: (path = '') =>
    request<FileListing>(`/files?path=${encodeURIComponent(path)}`),
  deleteFile: (path: string, recursive = false) =>
    request<void>(
      `/files?path=${encodeURIComponent(path)}&recursive=${recursive ? 1 : 0}`,
      { method: 'DELETE' },
    ),
  createShareLink: (path: string) =>
    request<ShareLink>('/files/share', {
      method: 'POST',
      body: JSON.stringify({ path }),
    }),
  shareUrl: (token: string) => `/api/share/${encodeURIComponent(token)}`,
  contentUrl: (path: string, inline = false) =>
    `/api/files/content?path=${encodeURIComponent(path)}&inline=${inline ? 1 : 0}`,
  bilibiliQrCode: () =>
    request<BilibiliQrCode>('/bilibili/qrcode', { method: 'POST' }),
  bilibiliQrPoll: (key: string) =>
    request<BilibiliPoll>(`/bilibili/qrcode/poll?key=${encodeURIComponent(key)}`),
  bilibiliStatus: () => request<BilibiliStatus>('/bilibili/status'),
  bilibiliLogout: () =>
    request<{ ok: boolean }>('/bilibili/logout', { method: 'POST' }),
  bangumiFollow: (type: 1 | 2, page = 1) =>
    request<BangumiFollowPage>(`/bangumi/follow?type=${type}&page=${page}`),
  bangumiSubscriptions: () =>
    request<{ subscriptions: BangumiSubscription[] }>('/bangumi/subscriptions'),
  bangumiSubscribe: (payload: {
    season_id: number
    media_type: 1 | 2
    mode: 'watch' | 'all'
  }) =>
    request<BangumiSubscribeResult>('/bangumi/subscriptions', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
  bangumiUpdateSubscription: (
    id: string,
    payload: { enabled?: boolean; auto_download?: boolean },
  ) =>
    request<BangumiSubscription>(`/bangumi/subscriptions/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(payload),
    }),
  bangumiDeleteSubscription: (id: string) =>
    request<void>(`/bangumi/subscriptions/${id}`, { method: 'DELETE' }),
  bangumiCheckSubscription: (id: string) =>
    request<BangumiCheckResult>(`/bangumi/subscriptions/${id}/check`, {
      method: 'POST',
    }),
  bangumiDownloadAll: (id: string) =>
    request<BangumiDownloadAllResult>(`/bangumi/subscriptions/${id}/download-all`, {
      method: 'POST',
    }),
  bangumiSeason: (seasonId: number) =>
    request<BangumiSeasonDetail>(`/bangumi/season/${seasonId}`),
  bangumiDownloadEpisodes: (payload: {
    season_id: number
    episode_indices: number[]
  }) =>
    request<BangumiDownloadResult>('/bangumi/download', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
}
