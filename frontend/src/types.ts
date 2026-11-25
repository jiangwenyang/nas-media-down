export interface VideoInfo {
  id: string | null
  title: string
  duration: number | null
  thumbnail: string | null
  uploader: string | null
  webpage_url: string | null
}

export interface PlaylistEntry {
  index: number
  id: string | null
  title: string
  duration: number | null
  thumbnail: string | null
}

export interface PlaylistInfo {
  id: string | null
  title: string
  count: number
  truncated: boolean
  entries: PlaylistEntry[]
}

export interface ProbeResult {
  kind: 'video' | 'playlist'
  video: VideoInfo | null
  playlist: PlaylistInfo | null
}

export type JobStatus =
  | 'queued'
  | 'running'
  | 'partial'
  | 'completed'
  | 'failed'
  | 'cancelled'
  | 'interrupted'

export type ItemStatus =
  | 'pending'
  | 'downloading'
  | 'processing'
  | 'done'
  | 'failed'
  | 'cancelled'

export interface JobItem {
  idx: number
  title: string
  thumbnail: string | null
  duration: number | null
  status: ItemStatus
  progress: number
  downloaded_bytes: number | null
  total_bytes: number | null
  speed: number | null
  eta: number | null
  filename: string | null
  error: string | null
}

export interface Job {
  id: string
  url: string
  kind: 'video' | 'playlist'
  title: string
  playlist_title: string | null
  status: JobStatus
  progress: number
  error: string | null
  created_at: number
  started_at: number | null
  finished_at: number | null
  item_count: number
  items?: JobItem[]
}

export interface JobDetail {
  job: Job
  items: JobItem[]
}

export interface FileEntry {
  name: string
  path: string
  is_dir: boolean
  size: number
  mtime: number
  mime: string | null
}

export interface FileListing {
  path: string
  parent: string | null
  entries: FileEntry[]
}

export interface ShareLink {
  token: string
  expires_at: number
}

export interface CreateJobPayload {
  url: string
  kind: 'video' | 'playlist'
  playlist_id?: string | null
  playlist_title?: string | null
  entries: Array<{
    index: number
    title: string
    duration?: number | null
    thumbnail?: string | null
  }>
}

export interface BilibiliQrCode {
  url: string
  key: string
}

export interface BilibiliPoll {
  code: number
  status: string
  logged_in: boolean
  uname: string | null
  vip: boolean
}

export interface BilibiliStatus {
  logged_in: boolean
  uname: string | null
  vip: boolean
  expires_at: number | null
}

export interface BangumiNewEp {
  title: string | null
  pub_time: string | null
}

export interface BangumiFollowItem {
  season_id: number
  media_id: number | null
  type: 1 | 2
  title: string
  cover: string | null
  season_title: string | null
  total_count: number
  is_finish: boolean
  new_ep: BangumiNewEp | null
  url: string
  subscribed: boolean
  subscription_id: string | null
}

export interface BangumiFollowPage {
  items: BangumiFollowItem[]
  page: number
  total: number
  has_more: boolean
}

export interface BangumiSubscription {
  id: string
  season_id: number
  media_id: number | null
  type: 1 | 2
  title: string
  cover: string | null
  url: string
  auto_download: boolean
  enabled: boolean
  last_check_at: number | null
  last_error: string | null
  created_at: number
  episode_count: number
  done_count: number
  queued_count: number
  failed_count: number
  skipped_count: number
  latest_title: string | null
  latest_status: 'skipped' | 'queued' | 'done' | 'failed' | null
}

export interface BangumiSubscribeResult {
  subscription: BangumiSubscription | null
  job_count: number
  error: string | null
}

export interface BangumiCheckResult {
  checked?: boolean
  busy?: boolean
  new_episodes: number
  job_count: number
  error?: string | null
}

export interface BangumiDownloadAllResult {
  episode_count: number
  job_count: number
  error: string | null
  subscription: BangumiSubscription | null
}

export type BangumiEpisodeStatus = 'skipped' | 'queued' | 'done' | 'failed' | null

export interface BangumiSeasonEpisode {
  ep_id: number
  idx: number
  title: string
  long_title: string | null
  duration: number | null
  cover: string | null
  pub_time: number | null
  url: string
  status: BangumiEpisodeStatus
}

export interface BangumiSeasonDetail {
  season_id: number
  media_id: number | null
  title: string
  season_title: string | null
  cover: string | null
  total_count: number
  episodes: BangumiSeasonEpisode[]
  subscribed: boolean
}

export type BangumiDownloadResult = BangumiDownloadAllResult
