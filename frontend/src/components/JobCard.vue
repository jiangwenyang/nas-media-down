<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { ChevronDown, RotateCcw, Trash2, TriangleAlert, X } from 'lucide-vue-next'
import { api, errorMessage } from '../api'
import { useJobs } from '../composables/useJobs'
import { useToast } from '../composables/useToast'
import type {
  CreateJobPayload,
  ItemStatus,
  Job,
  JobItem,
  JobStatus,
} from '../types'
import { formatBytes, formatDate, formatEta, formatSpeed } from '../utils/format'
import ConfirmDialog from './ConfirmDialog.vue'

const props = defineProps<{
  job: Job
}>()

const { refresh } = useJobs()
const { push } = useToast()

const isActive = computed(
  () => props.job.status === 'queued' || props.job.status === 'running',
)
const expanded = ref(isActive.value)
const detailItems = ref<JobItem[] | null>(null)
const loadingDetail = ref(false)
const busy = ref(false)
const confirmDelete = ref(false)

const items = computed<JobItem[]>(() => props.job.items ?? detailItems.value ?? [])
const percent = computed(() =>
  Math.min(100, Math.max(0, Math.round(props.job.progress * 100))),
)
const currentItem = computed(
  () =>
    items.value.find((item) => item.status === 'downloading') ??
    items.value.find((item) => item.status === 'processing') ??
    null,
)
const canRetry = computed(() =>
  ['failed', 'cancelled', 'interrupted'].includes(props.job.status),
)

const STATUS_META: Record<JobStatus, { label: string; cls: string }> = {
  queued: { label: '排队中', cls: 'border-slate-400/20 bg-slate-500/10 text-slate-300' },
  running: { label: '下载中', cls: 'border-cyan-300/30 bg-cyan-400/10 text-cyan-200' },
  partial: { label: '部分完成', cls: 'border-amber-300/30 bg-amber-400/10 text-amber-200' },
  completed: {
    label: '已完成',
    cls: 'border-emerald-300/30 bg-emerald-400/10 text-emerald-200',
  },
  failed: { label: '失败', cls: 'border-rose-300/30 bg-rose-400/10 text-rose-200' },
  cancelled: { label: '已取消', cls: 'border-slate-400/20 bg-slate-500/10 text-slate-400' },
  interrupted: {
    label: '已中断',
    cls: 'border-amber-300/30 bg-amber-400/10 text-amber-200',
  },
}

const ITEM_LABELS: Record<ItemStatus, string> = {
  pending: '等待中',
  downloading: '下载中',
  processing: '合并中',
  done: '完成',
  failed: '失败',
  cancelled: '已取消',
}

const meta = computed(() => STATUS_META[props.job.status])

function itemLabel(item: JobItem): string {
  if (item.status === 'downloading') return `${Math.round(item.progress * 100)}%`
  return ITEM_LABELS[item.status]
}

function itemClass(item: JobItem): string {
  if (item.status === 'done') return 'text-emerald-300'
  if (item.status === 'failed') return 'text-rose-300'
  if (item.status === 'downloading' || item.status === 'processing') return 'text-cyan-300'
  return 'text-slate-500'
}

watch(
  () => [expanded.value, props.job.items, props.job.status] as const,
  async () => {
    if (!expanded.value || props.job.items || detailItems.value || loadingDetail.value) return
    loadingDetail.value = true
    try {
      detailItems.value = (await api.getJob(props.job.id)).items
    } catch (error) {
      push(errorMessage(error), 'error')
    } finally {
      loadingDetail.value = false
    }
  },
  { immediate: true },
)

async function cancelJob(): Promise<void> {
  busy.value = true
  try {
    await api.cancelJob(props.job.id)
    push('已请求取消任务', 'info')
    await refresh()
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    busy.value = false
  }
}

async function removeJob(): Promise<void> {
  busy.value = true
  try {
    await api.deleteJob(props.job.id)
    confirmDelete.value = false
    push('已删除任务记录', 'success')
    await refresh()
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    busy.value = false
  }
}

async function retry(): Promise<void> {
  busy.value = true
  try {
    let source = items.value
    if (source.length === 0) {
      source = (await api.getJob(props.job.id)).items
    }
    const payload: CreateJobPayload = {
      url: props.job.url,
      kind: props.job.kind,
      playlist_title: props.job.playlist_title,
      entries: source.map((item) => ({
        index: props.job.kind === 'video' ? 1 : item.idx,
        title: item.title,
        duration: item.duration,
        thumbnail: item.thumbnail,
      })),
    }
    await api.createJob(payload)
    push('已重新加入下载队列', 'success')
    await refresh()
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <article class="glass-card p-4 sm:p-5">
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-2">
          <span class="status-pill" :class="meta.cls">
            <span
              class="h-1.5 w-1.5 rounded-full"
              :class="isActive ? 'animate-pulse bg-cyan-300' : 'bg-current opacity-70'"
            />
            {{ meta.label }}
          </span>
          <span class="text-[11px] text-slate-500">
            {{ job.kind === 'playlist' ? `播放列表 · ${job.item_count} 个` : '单视频' }}
            · {{ formatDate(job.created_at) }}
          </span>
        </div>
        <h3 class="mt-2 line-clamp-2 text-sm font-medium text-slate-100 sm:text-base">
          {{ job.title }}
        </h3>
      </div>

      <div class="flex shrink-0 items-center gap-1">
        <button
          v-if="isActive"
          type="button"
          class="icon-btn"
          title="取消任务"
          :disabled="busy"
          @click="cancelJob"
        >
          <X :size="15" />
        </button>
        <button
          v-if="canRetry"
          type="button"
          class="icon-btn"
          title="重新下载"
          :disabled="busy"
          @click="retry"
        >
          <RotateCcw :size="15" />
        </button>
        <button
          v-if="!isActive"
          type="button"
          class="icon-btn"
          title="删除记录"
          :disabled="busy"
          @click="confirmDelete = true"
        >
          <Trash2 :size="15" />
        </button>
        <button
          v-if="job.item_count > 1"
          type="button"
          class="icon-btn"
          :title="expanded ? '收起条目' : '展开条目'"
          @click="expanded = !expanded"
        >
          <ChevronDown
            :size="15"
            class="transition-transform duration-200"
            :class="{ 'rotate-180': !expanded }"
          />
        </button>
      </div>
    </div>

    <p
      v-if="job.error"
      class="mt-2 flex items-start gap-1.5 text-xs leading-relaxed text-rose-300/90"
    >
      <TriangleAlert :size="14" class="mt-0.5 shrink-0" />
      <span>{{ job.error }}</span>
    </p>

    <div class="mt-3">
      <div class="progress-track">
        <div
          class="progress-fill"
          :class="{ 'progress-running': isActive }"
          :style="{ width: `${percent}%` }"
        />
      </div>
      <div class="mt-1.5 flex items-center justify-between gap-3 text-[11px] text-slate-500">
        <span>{{ percent }}%</span>
        <span v-if="isActive && currentItem" class="truncate">
          {{ formatSpeed(currentItem.speed) }}
          <template v-if="currentItem.eta"> · {{ formatEta(currentItem.eta) }}</template>
        </span>
        <span v-else-if="job.finished_at">{{ formatDate(job.finished_at) }}</span>
      </div>
    </div>

    <div
      v-if="expanded && job.item_count > 1"
      class="mt-3 space-y-2 border-t border-white/5 pt-3"
    >
      <div v-if="loadingDetail" class="space-y-2">
        <div v-for="n in 3" :key="n" class="h-9 animate-pulse rounded-lg bg-white/[0.03]" />
      </div>
      <div
        v-for="item in items"
        v-else
        :key="item.idx"
        class="rounded-lg bg-white/[0.02] px-3 py-2"
      >
        <div class="flex items-center gap-2 text-xs">
          <span class="w-6 shrink-0 text-right text-[11px] text-slate-600">{{ item.idx }}</span>
          <span class="min-w-0 flex-1 truncate text-slate-300">{{ item.title }}</span>
          <span class="shrink-0 text-[11px] tabular-nums" :class="itemClass(item)">
            {{ itemLabel(item) }}
          </span>
        </div>
        <div class="mt-1.5 flex items-center gap-2">
          <div class="progress-track h-1">
            <div
              class="progress-fill"
              :class="{ 'progress-running': item.status === 'downloading' }"
              :style="{ width: `${Math.round(item.progress * 100)}%` }"
            />
          </div>
          <span class="w-16 shrink-0 text-right text-[10px] text-slate-600">
            {{ formatBytes(item.total_bytes) }}
          </span>
        </div>
        <p v-if="item.error" class="mt-1 text-[11px] text-rose-300/80">{{ item.error }}</p>
      </div>
    </div>

    <ConfirmDialog
      v-if="confirmDelete"
      title="删除任务记录"
      message="只会移除任务历史，不会删除 NAS 上已下载的文件。"
      confirm-label="删除记录"
      :busy="busy"
      @cancel="confirmDelete = false"
      @confirm="removeJob"
    />
  </article>
</template>
