import { computed, ref } from 'vue'
import { api, errorMessage } from '../api'
import type { Job } from '../types'

const jobs = ref<Job[]>([])
const loading = ref(false)
const error = ref<string | null>(null)
let running = false
let timer: number | undefined

const active = computed(() =>
  jobs.value.filter((job) => job.status === 'queued' || job.status === 'running'),
)

async function fetchJobs(): Promise<void> {
  loading.value = true
  try {
    const data = await api.listJobs()
    jobs.value = data.jobs
    error.value = null
  } catch (err) {
    error.value = errorMessage(err)
  } finally {
    loading.value = false
  }
}

function schedule(): void {
  if (!running) return
  const delay = active.value.length > 0 ? 1000 : 10000
  timer = window.setTimeout(async () => {
    await fetchJobs()
    schedule()
  }, document.hidden ? delay * 3 : delay)
}

function start(): void {
  if (running) return
  running = true
  void fetchJobs().then(schedule)
}

function stop(): void {
  running = false
  if (timer !== undefined) {
    window.clearTimeout(timer)
    timer = undefined
  }
}

/** 任务列表轮询（模块级单例）：有活动任务时 1 秒刷新，空闲时 10 秒。 */
export function useJobs() {
  return { jobs, loading, error, active, refresh: fetchJobs, start, stop }
}
