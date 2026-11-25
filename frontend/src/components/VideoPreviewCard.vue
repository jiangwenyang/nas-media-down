<script setup lang="ts">
import { Download, Film, User } from 'lucide-vue-next'
import type { VideoInfo } from '../types'
import { formatDuration } from '../utils/format'

defineProps<{
  video: VideoInfo
  busy: boolean
}>()

defineEmits<{
  download: []
}>()
</script>

<template>
  <article class="glass-card animate-float-in overflow-hidden">
    <div class="flex flex-col sm:flex-row">
      <div
        class="relative aspect-video w-full shrink-0 overflow-hidden bg-slate-900/80 sm:aspect-auto sm:w-64"
      >
        <img
          v-if="video.thumbnail"
          :src="video.thumbnail"
          :alt="video.title"
          referrerpolicy="no-referrer"
          loading="lazy"
          class="h-full min-h-40 w-full object-cover"
        />
        <div
          v-else
          class="flex h-full min-h-40 w-full items-center justify-center text-slate-700"
        >
          <Film :size="40" :stroke-width="1.5" />
        </div>
        <span
          class="absolute right-2 bottom-2 rounded-md bg-slate-950/80 px-1.5 py-0.5 text-[11px] font-medium text-slate-200 backdrop-blur"
        >
          {{ formatDuration(video.duration) }}
        </span>
      </div>

      <div class="flex flex-1 flex-col justify-between gap-4 p-4 sm:p-5">
        <div>
          <p class="text-[11px] font-medium tracking-wide text-cyan-300/80">单视频</p>
          <h2 class="mt-1 line-clamp-2 text-base leading-snug font-semibold text-white sm:text-lg">
            {{ video.title }}
          </h2>
          <p class="mt-1.5 flex items-center gap-1.5 text-xs text-slate-400">
            <User :size="13" />
            {{ video.uploader || '未知作者' }}
          </p>
        </div>

        <button type="button" class="btn-primary self-start" :disabled="busy" @click="$emit('download')">
          <Download :size="16" />
          {{ busy ? '正在创建任务…' : '下载此视频' }}
        </button>
      </div>
    </div>
  </article>
</template>
