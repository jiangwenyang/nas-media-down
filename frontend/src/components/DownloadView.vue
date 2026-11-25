<script setup lang="ts">
import { computed, ref } from 'vue'
import { ListChecks, ListVideo, TriangleAlert } from 'lucide-vue-next'
import { api, errorMessage } from '../api'
import { useJobs } from '../composables/useJobs'
import { useToast } from '../composables/useToast'
import type { CreateJobPayload, PlaylistEntry, ProbeResult } from '../types'
import UrlComposer from './UrlComposer.vue'
import VideoPreviewCard from './VideoPreviewCard.vue'
import PlaylistDialog from './PlaylistDialog.vue'
import JobCard from './JobCard.vue'

const emit = defineEmits<{
  'open-jobs': []
}>()

const { active, refresh } = useJobs()
const { push } = useToast()

const url = ref('')
const probing = ref(false)
const probeError = ref('')
const result = ref<ProbeResult | null>(null)
const playlistOpen = ref(false)
const submitting = ref(false)

const playlist = computed(() => result.value?.playlist ?? null)
const singleVideo = computed(() => result.value?.video ?? null)
const visibleActive = computed(() => active.value.slice(0, 4))

async function probe(): Promise<void> {
  const value = url.value.trim()
  if (!value || probing.value) return
  probing.value = true
  probeError.value = ''
  result.value = null
  try {
    const data = await api.probe(value)
    result.value = data
    if (data.kind === 'playlist') {
      playlistOpen.value = true
    }
  } catch (error) {
    probeError.value = errorMessage(error)
  } finally {
    probing.value = false
  }
}

async function create(payload: CreateJobPayload): Promise<void> {
  if (submitting.value) return
  submitting.value = true
  try {
    const response = await api.createJob(payload)
    push(`已加入下载队列，共 ${response.item_count} 个视频`, 'success')
    playlistOpen.value = false
    await refresh()
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    submitting.value = false
  }
}

async function downloadVideo(): Promise<void> {
  if (!singleVideo.value) return
  await create({
    url: url.value.trim(),
    kind: 'video',
    entries: [
      {
        index: 1,
        title: singleVideo.value.title,
        duration: singleVideo.value.duration,
        thumbnail: singleVideo.value.thumbnail,
      },
    ],
  })
}

async function submitPlaylist(payload: {
  mode: 'selected' | 'all' | 'current'
  entries: PlaylistEntry[]
}): Promise<void> {
  if (payload.mode === 'current') {
    await downloadVideo()
    return
  }
  if (!playlist.value) return
  await create({
    url: url.value.trim(),
    kind: 'playlist',
    playlist_id: playlist.value.id,
    playlist_title: playlist.value.title,
    entries: payload.entries.map((entry) => ({
      index: entry.index,
      title: entry.title,
      duration: entry.duration,
      thumbnail: entry.thumbnail,
    })),
  })
}
</script>

<template>
  <div class="space-y-6">
    <header class="pt-2 sm:pt-4">
      <h1 class="text-balance text-2xl font-semibold tracking-tight text-white sm:text-3xl">
        粘贴网址，
        <span class="bg-gradient-to-r from-cyan-300 via-sky-300 to-indigo-300 bg-clip-text text-transparent">
          剩下的交给 NAS
        </span>
      </h1>
      <p class="mt-2 text-sm leading-relaxed text-slate-400">
        自动识别视频与关联播放列表，勾选后按最佳画质下载到映射目录。
      </p>
    </header>

    <UrlComposer v-model="url" :loading="probing" @submit="probe" />

    <p
      v-if="probeError"
      class="flex items-start gap-2 rounded-xl border border-rose-300/20 bg-rose-500/10 px-3.5 py-2.5 text-xs leading-relaxed text-rose-200"
    >
      <TriangleAlert :size="15" class="mt-0.5 shrink-0" />
      <span>{{ probeError }}</span>
    </p>

    <div v-if="probing" class="glass-card flex gap-4 p-4 sm:p-5">
      <div class="aspect-video w-32 shrink-0 animate-pulse rounded-xl bg-white/[0.06] sm:w-56" />
      <div class="flex-1 space-y-3 py-1">
        <div class="h-3 w-20 animate-pulse rounded bg-white/[0.06]" />
        <div class="h-5 w-3/4 animate-pulse rounded bg-white/[0.08]" />
        <div class="h-3 w-1/3 animate-pulse rounded bg-white/[0.06]" />
        <div class="h-9 w-32 animate-pulse rounded-xl bg-white/[0.06]" />
      </div>
    </div>

    <VideoPreviewCard
      v-else-if="result?.kind === 'video' && singleVideo"
      :video="singleVideo"
      :busy="submitting"
      @download="downloadVideo"
    />

    <article
      v-else-if="result?.kind === 'playlist' && playlist"
      class="glass-card animate-float-in p-4 sm:p-5"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center">
        <span
          class="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-indigo-400/10 text-indigo-200"
        >
          <ListVideo :size="22" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="text-[11px] font-medium tracking-wide text-cyan-300/80">
            播放列表 · {{ playlist.count }} 个视频
          </p>
          <h2 class="mt-1 line-clamp-2 text-base leading-snug font-semibold text-white">
            {{ playlist.title }}
          </h2>
          <p v-if="singleVideo" class="mt-1 truncate text-xs text-slate-400">
            当前视频：{{ singleVideo.title }}
          </p>
        </div>
        <div class="flex flex-col gap-2 sm:flex-row">
          <button
            v-if="singleVideo"
            type="button"
            class="btn-ghost"
            :disabled="submitting"
            @click="downloadVideo"
          >
            仅当前视频
          </button>
          <button type="button" class="btn-primary" :disabled="submitting" @click="playlistOpen = true">
            <ListChecks :size="16" />
            选择下载
          </button>
        </div>
      </div>
    </article>

    <section v-if="visibleActive.length > 0" class="space-y-3">
      <div class="flex items-center justify-between">
        <h2 class="text-sm font-medium text-slate-300">进行中的任务</h2>
        <button
          type="button"
          class="text-xs text-cyan-300/90 transition hover:text-cyan-200"
          @click="emit('open-jobs')"
        >
          查看全部
        </button>
      </div>
      <JobCard v-for="job in visibleActive" :key="job.id" :job="job" />
    </section>

    <PlaylistDialog
      v-if="playlistOpen && playlist"
      :playlist="playlist"
      :video="singleVideo"
      :busy="submitting"
      @close="playlistOpen = false"
      @submit="submitPlaylist"
    />
  </div>
</template>
