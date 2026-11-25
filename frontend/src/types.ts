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
