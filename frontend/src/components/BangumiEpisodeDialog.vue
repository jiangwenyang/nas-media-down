<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { Download, LoaderCircle, Search, TriangleAlert, X } from 'lucide-vue-next'
import { api, errorMessage } from '../api'
import type { BangumiEpisodeStatus, BangumiSeasonDetail } from '../types'
import { formatDuration } from '../utils/format'

const props = defineProps<{
  seasonId: number
  title: string
  subscribed: boolean
  busy: boolean
}>()

const emit = defineEmits<{
  close: []
  confirm: [payload: { indices: number[] }]
}>()

const detail = ref<BangumiSeasonDetail | null>(null)
const loading = ref(true)
const error = ref('')
const search = ref('')
const selected = ref<Set<number>>(new Set())

const STATUS_META: Record<
  Exclude<BangumiEpisodeStatus, null>,
  { label: string; cls: string }
> = {
  done: { label: '已完成', cls: 'text-emerald-300' },
  queued: { label: '排队中', cls: 'text-cyan-300' },
  failed: { label: '失败', cls: 'text-rose-300' },
  skipped: { label: '未下载', cls: 'text-slate-500' },
}

const episodes = computed(() => detail.value?.episodes ?? [])
const filtered = computed(() => {
  const keyword = search.value.trim().toLowerCase()
  if (!keyword) return episodes.value
  return episodes.value.filter(
    (ep) =>
      ep.title.toLowerCase().includes(keyword) ||
      (ep.long_title ?? '').toLowerCase().includes(keyword),
  )
})
const selectableFiltered = computed(() => filtered.value.filter(isSelectable))
const allSelected = computed(
  () =>
    selectableFiltered.value.length > 0 &&
    selectableFiltered.value.every((ep) => selected.value.has(ep.idx)),
)

/** 已完成或排队中的剧集不可重复选择。 */
function isSelectable(ep: { status: BangumiEpisodeStatus }): boolean {
  return ep.status !== 'done' && ep.status !== 'queued'
}

/** 返回剧集状态的展示文案与颜色。 */
function statusMeta(status: BangumiEpisodeStatus): { label: string; cls: string } | null {
  return status ? STATUS_META[status] : null
}

/** 加载剧集列表。 */
async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    detail.value = await api.bangumiSeason(props.seasonId)
  } catch (err) {
    error.value = errorMessage(err)
  } finally {
    loading.value = false
  }
}

function toggle(idx: number): void {
  const next = new Set(selected.value)
  if (next.has(idx)) next.delete(idx)
  else next.add(idx)
  selected.value = next
}

function selectAll(): void {
  const next = new Set(selected.value)
  if (allSelected.value) {
    for (const ep of selectableFiltered.value) next.delete(ep.idx)
  } else {
    for (const ep of selectableFiltered.value) next.add(ep.idx)
  }
  selected.value = next
}

function submit(): void {
  if (props.busy || selected.value.size === 0) return
  emit('confirm', { indices: [...selected.value].sort((a, b) => a - b) })
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Escape') emit('close')
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
  document.body.style.overflow = 'hidden'
  void load()
})

onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown)
  document.body.style.overflow = ''
})
</script>

<template>
  <Teleport to="body">
    <div
      class="animate-overlay-in fixed inset-0 z-50 flex items-end justify-center bg-slate-950/70 backdrop-blur-sm sm:items-center sm:p-6"
      @click.self="emit('close')"
    >
      <div
        class="animate-float-in glass-card flex max-h-[92vh] w-full max-w-2xl flex-col overflow-hidden rounded-t-3xl rounded-b-none sm:rounded-2xl"
      >
        <header class="flex items-start justify-between gap-3 border-b border-white/5 p-4 sm:p-5">
          <div class="min-w-0">
            <p class="flex items-center gap-1.5 text-[11px] font-medium tracking-wide text-cyan-300/80">
              <Download :size="13" />
              选择下载集数
            </p>
            <h2 class="mt-1 line-clamp-2 text-base font-semibold text-white sm:text-lg">
              {{ title }}
            </h2>
          </div>
          <button type="button" class="icon-btn shrink-0" aria-label="关闭" @click="emit('close')">
            <X :size="16" />
          </button>
        </header>

        <div v-if="loading" class="flex flex-col items-center gap-3 px-5 py-16 text-slate-500">
          <LoaderCircle :size="22" class="animate-spin" />
          <p class="text-xs">正在加载剧集…</p>
        </div>

        <div v-else-if="error" class="flex flex-col items-center gap-3 px-5 py-14 text-center">
          <TriangleAlert :size="22" class="text-rose-300" />
          <p class="max-w-md text-xs leading-relaxed text-rose-200">{{ error }}</p>
          <button type="button" class="btn-ghost px-3 py-2 text-xs" @click="load">重试</button>
        </div>

        <template v-else>
          <div class="border-b border-white/5 p-4 sm:px-5">
            <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
              <div class="relative flex-1">
                <Search
                  :size="15"
                  class="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-slate-500"
                />
                <input
                  v-model="search"
                  type="search"
                  placeholder="搜索剧集标题…"
                  class="field py-2.5 pl-9 text-xs"
                />
              </div>
              <div class="flex items-center justify-between gap-2 sm:justify-end">
                <span class="text-[11px] text-slate-500">
                  已选 {{ selected.size }} 集 · 共 {{ episodes.length }} 集
                </span>
                <button
                  type="button"
                  class="btn-ghost px-3 py-2 text-xs"
                  :disabled="selectableFiltered.length === 0"
                  @click="selectAll"
                >
                  {{ allSelected ? '取消全选' : '全选可下载' }}
                </button>
              </div>
            </div>
            <p v-if="!subscribed" class="mt-2 text-[11px] text-slate-500">
              未追更：本次只下载所选剧集，不会自动跟踪后续更新。
            </p>
          </div>

          <div class="min-h-0 flex-1 overflow-y-auto overscroll-contain">
            <div v-if="filtered.length === 0" class="px-5 py-12 text-center text-sm text-slate-500">
              没有匹配的剧集
            </div>
            <label
              v-for="ep in filtered"
              :key="ep.idx"
              class="flex items-center gap-3 border-b border-white/[0.04] px-4 py-2.5 transition sm:px-5"
              :class="
                isSelectable(ep)
                  ? 'cursor-pointer hover:bg-white/[0.03]'
                  : 'cursor-not-allowed opacity-60'
              "
            >
              <input
                type="checkbox"
                class="h-4 w-4 shrink-0 rounded border-white/20 accent-cyan-400"
                :checked="selected.has(ep.idx)"
                :disabled="!isSelectable(ep)"
                @change="toggle(ep.idx)"
              />
              <span class="w-8 shrink-0 text-right text-[11px] text-slate-600">{{ ep.idx }}</span>
              <span class="min-w-0 flex-1">
                <span class="line-clamp-1 text-xs leading-snug text-slate-200 sm:text-sm">
                  {{ ep.title }}
                </span>
                <span
                  v-if="ep.long_title && ep.long_title !== ep.title"
                  class="line-clamp-1 text-[11px] text-slate-500"
                >
                  {{ ep.long_title }}
                </span>
              </span>
              <span class="shrink-0 text-[11px] text-slate-500">
                {{ formatDuration(ep.duration) }}
              </span>
              <span
                v-if="statusMeta(ep.status)"
                class="w-14 shrink-0 text-right text-[11px]"
                :class="statusMeta(ep.status)?.cls"
              >
                {{ statusMeta(ep.status)?.label }}
              </span>
            </label>
          </div>

          <footer class="border-t border-white/10 p-4 sm:p-5">
            <div class="flex flex-col gap-2 sm:flex-row sm:justify-end">
              <button type="button" class="btn-ghost" :disabled="busy" @click="emit('close')">
                取消
              </button>
              <button
                type="button"
                class="btn-primary"
                :disabled="busy || selected.size === 0"
                @click="submit"
              >
                {{ busy ? '正在创建…' : `下载选中 ${selected.size} 集` }}
              </button>
            </div>
          </footer>
        </template>
      </div>
    </div>
  </Teleport>
</template>
