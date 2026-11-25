<script setup lang="ts">
import { computed, onMounted, onUnmounted } from 'vue'
import { Download, X } from 'lucide-vue-next'
import { api } from '../api'
import type { FileEntry } from '../types'
import { formatBytes } from '../utils/format'

const props = defineProps<{
  entry: FileEntry
}>()

const emit = defineEmits<{
  close: []
}>()

const kind = computed<'video' | 'audio' | 'image' | 'pdf' | 'other'>(() => {
  const mime = props.entry.mime ?? ''
  if (mime.startsWith('video/')) return 'video'
  if (mime.startsWith('audio/')) return 'audio'
  if (mime.startsWith('image/')) return 'image'
  if (mime === 'application/pdf') return 'pdf'
  return 'other'
})

const inlineUrl = computed(() => api.contentUrl(props.entry.path, true))
const downloadUrl = computed(() => api.contentUrl(props.entry.path, false))

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
      class="animate-overlay-in fixed inset-0 z-[60] flex items-center justify-center bg-slate-950/80 p-3 backdrop-blur-sm sm:p-6"
      @click.self="emit('close')"
    >
      <div class="animate-float-in glass-card flex max-h-[92vh] w-full max-w-4xl flex-col overflow-hidden">
        <header class="flex items-center justify-between gap-3 border-b border-white/5 px-4 py-3 sm:px-5">
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-slate-100">{{ entry.name }}</p>
            <p class="mt-0.5 text-[11px] text-slate-500">{{ formatBytes(entry.size) }}</p>
          </div>
          <div class="flex shrink-0 items-center gap-1.5">
            <a :href="downloadUrl" class="icon-btn" title="下载文件" download>
              <Download :size="15" />
            </a>
            <button type="button" class="icon-btn" aria-label="关闭预览" @click="emit('close')">
              <X :size="15" />
            </button>
          </div>
        </header>

        <div class="flex min-h-0 flex-1 items-center justify-center bg-black/50 p-3 sm:p-5">
          <video
            v-if="kind === 'video'"
            :src="inlineUrl"
            controls
            playsinline
            preload="metadata"
            class="max-h-[72vh] w-full rounded-lg bg-black"
          />
          <audio v-else-if="kind === 'audio'" :src="inlineUrl" controls class="w-full" />
          <img
            v-else-if="kind === 'image'"
            :src="inlineUrl"
            :alt="entry.name"
            class="max-h-[72vh] max-w-full rounded-lg object-contain"
          />
          <iframe
            v-else-if="kind === 'pdf'"
            :src="inlineUrl"
            title="PDF 预览"
            class="h-[72vh] w-full rounded-lg bg-white"
          />
          <div v-else class="py-16 text-center">
            <p class="text-sm text-slate-400">该文件类型不支持在线预览</p>
            <a :href="downloadUrl" class="btn-primary mt-4" download>下载文件</a>
          </div>
        </div>

        <p
          v-if="kind === 'video'"
          class="border-t border-white/5 px-4 py-2 text-[11px] text-slate-500 sm:px-5"
        >
          浏览器若不支持该编码（如部分 mkv），请使用右上角按钮下载后在播放器中观看。
        </p>
      </div>
    </div>
  </Teleport>
</template>
