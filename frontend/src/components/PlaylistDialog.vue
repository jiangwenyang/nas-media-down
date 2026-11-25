<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { ListChecks, Search, X } from 'lucide-vue-next'
import type { PlaylistEntry, PlaylistInfo, VideoInfo } from '../types'
import { formatDuration } from '../utils/format'

type SubmitMode = 'selected' | 'all' | 'current'

const props = defineProps<{
  playlist: PlaylistInfo
  video: VideoInfo | null
  busy: boolean
}>()

const emit = defineEmits<{
  close: []
  submit: [payload: { mode: SubmitMode; entries: PlaylistEntry[] }]
}>()

const search = ref('')
const selected = ref<Set<number>>(new Set())

const filtered = computed(() => {
  const keyword = search.value.trim().toLowerCase()
  if (!keyword) return props.playlist.entries
  return props.playlist.entries.filter((entry) =>
    entry.title.toLowerCase().includes(keyword),
  )
})

const allFilteredSelected = computed(
  () =>
    filtered.value.length > 0 &&
    filtered.value.every((entry) => selected.value.has(entry.index)),
)

function toggle(index: number): void {
  const next = new Set(selected.value)
  if (next.has(index)) next.delete(index)
  else next.add(index)
  selected.value = next
}

function selectAll(): void {
  if (allFilteredSelected.value) {
    const next = new Set(selected.value)
    for (const entry of filtered.value) next.delete(entry.index)
    selected.value = next
    return
  }
  const next = new Set(selected.value)
  for (const entry of filtered.value) next.add(entry.index)
  selected.value = next
}

function submit(mode: SubmitMode): void {
  if (props.busy) return
  if (mode === 'selected') {
    if (selected.value.size === 0) return
    emit('submit', {
      mode,
      entries: props.playlist.entries.filter((entry) => selected.value.has(entry.index)),
    })
    return
  }
  emit('submit', {
    mode,
    entries: mode === 'all' ? props.playlist.entries : [],
  })
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Escape') emit('close')
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
  document.body.style.overflow = 'hidden'
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
              <ListChecks :size="13" />
              播放列表 · {{ playlist.count }} 个视频
            </p>
            <h2 class="mt-1 line-clamp-2 text-base font-semibold text-white sm:text-lg">
              {{ playlist.title }}
            </h2>
          </div>
          <button type="button" class="icon-btn shrink-0" aria-label="关闭" @click="emit('close')">
            <X :size="16" />
          </button>
        </header>

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
                placeholder="搜索视频标题…"
                class="field py-2.5 pl-9 text-xs"
              />
            </div>
            <div class="flex items-center justify-between gap-2 sm:justify-end">
              <span class="text-[11px] text-slate-500">已选 {{ selected.size }} 个</span>
              <button type="button" class="btn-ghost px-3 py-2 text-xs" @click="selectAll">
                {{ allFilteredSelected ? '取消全选' : '全选' }}
              </button>
            </div>
          </div>
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto overscroll-contain">
          <div v-if="filtered.length === 0" class="px-5 py-12 text-center text-sm text-slate-500">
            没有匹配的视频
          </div>
          <label
            v-for="entry in filtered"
            :key="entry.index"
            class="flex cursor-pointer items-center gap-3 border-b border-white/[0.04] px-4 py-2.5 transition hover:bg-white/[0.03] sm:px-5"
          >
            <input
              type="checkbox"
              class="h-4 w-4 shrink-0 cursor-pointer rounded border-white/20 accent-cyan-400"
              :checked="selected.has(entry.index)"
              @change="toggle(entry.index)"
            />
            <span class="w-7 shrink-0 text-right text-[11px] text-slate-600">{{ entry.index }}</span>
            <img
              v-if="entry.thumbnail"
              :src="entry.thumbnail"
              :alt="entry.title"
              referrerpolicy="no-referrer"
              loading="lazy"
              class="h-11 w-20 shrink-0 rounded-md bg-slate-900 object-cover"
            />
            <span v-else class="h-11 w-20 shrink-0 rounded-md bg-white/[0.04]" />
            <span class="min-w-0 flex-1">
              <span class="line-clamp-2 text-xs leading-snug text-slate-200 sm:text-sm">
                {{ entry.title }}
              </span>
            </span>
            <span class="shrink-0 text-[11px] text-slate-500">
              {{ formatDuration(entry.duration) }}
            </span>
          </label>
        </div>

        <footer class="border-t border-white/10 p-4 sm:p-5">
          <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <button
              v-if="video"
              type="button"
              class="btn-ghost"
              :disabled="busy"
              @click="submit('current')"
            >
              仅下载当前视频
            </button>
            <div class="flex flex-col gap-2 sm:flex-row sm:justify-end">
              <button type="button" class="btn-ghost" :disabled="busy" @click="submit('all')">
                下载全部 {{ playlist.entries.length }} 个
              </button>
              <button
                type="button"
                class="btn-primary"
                :disabled="busy || selected.size === 0"
                @click="submit('selected')"
              >
                {{ busy ? '正在创建…' : `下载选中 ${selected.size} 个` }}
              </button>
            </div>
          </div>
          <p v-if="playlist.truncated" class="mt-2 text-[11px] text-amber-200/80">
            列表共 {{ playlist.count }} 个视频，当前仅加载前 {{ playlist.entries.length }} 个
          </p>
        </footer>
      </div>
    </div>
  </Teleport>
</template>
