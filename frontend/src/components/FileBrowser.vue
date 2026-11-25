<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ChevronRight,
  Download,
  Eye,
  File,
  FileHeadphone,
  FileImage,
  FileText,
  FilePlay,
  Folder,
  FolderOpen,
  RefreshCw,
  Trash2,
} from 'lucide-vue-next'
import { api, errorMessage } from '../api'
import { useToast } from '../composables/useToast'
import type { FileEntry, FileListing } from '../types'
import { formatBytes, formatDate } from '../utils/format'
import PreviewDialog from './PreviewDialog.vue'
import MediaLinkDialog from './MediaLinkDialog.vue'
import ConfirmDialog from './ConfirmDialog.vue'

const { push } = useToast()

const listing = ref<FileListing | null>(null)
const path = ref('')
const loading = ref(false)
const error = ref('')
const preview = ref<FileEntry | null>(null)
const mediaLink = ref<FileEntry | null>(null)
const pendingDelete = ref<FileEntry | null>(null)
const deleting = ref(false)

const crumbs = computed(() => {
  if (!listing.value?.path) return []
  const parts = listing.value.path.split('/')
  return parts.map((name, index) => ({
    name,
    path: parts.slice(0, index + 1).join('/'),
  }))
})

const deleteMessage = computed(() =>
  pendingDelete.value?.is_dir
    ? '将递归删除该目录及其中所有文件，删除后不可恢复。'
    : '该文件将被永久删除，删除后不可恢复。',
)

async function load(target?: string): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    const data = await api.listFiles(target ?? path.value)
    listing.value = data
    path.value = data.path
  } catch (err) {
    error.value = errorMessage(err)
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  void load('')
})

function isVideo(entry: FileEntry): boolean {
  return (
    (entry.mime ?? '').startsWith('video/') ||
    /\.(mkv|mp4|m4v|mov|webm|avi|flv|ts|wmv|3gp)$/i.test(entry.name)
  )
}

function isAudio(entry: FileEntry): boolean {
  return (
    (entry.mime ?? '').startsWith('audio/') ||
    /\.(mp3|m4a|aac|flac|wav|opus|ogg|oga|aiff|alac)$/i.test(entry.name)
  )
}

function isMedia(entry: FileEntry): boolean {
  return isVideo(entry) || isAudio(entry)
}

function isImage(entry: FileEntry): boolean {
  return (
    (entry.mime ?? '').startsWith('image/') ||
    /\.(jpg|jpeg|png|gif|webp|heic|heif|bmp|tiff)$/i.test(entry.name)
  )
}

function isPDF(entry: FileEntry): boolean {
  return entry.mime === 'application/pdf' || /\.pdf$/i.test(entry.name)
}

function isPreviewable(entry: FileEntry): boolean {
  return isMedia(entry) || isImage(entry) || isPDF(entry)
}

function openEntry(entry: FileEntry): void {
  if (entry.is_dir) {
    void load(entry.path)
    return
  }
  if (isMedia(entry)) {
    mediaLink.value = entry
    return
  }
  if (isPreviewable(entry)) {
    preview.value = entry
  }
}

function openPreview(entry: FileEntry): void {
  if (isMedia(entry)) {
    mediaLink.value = entry
    return
  }
  if (isPreviewable(entry)) {
    preview.value = entry
  }
}

function iconFor(entry: FileEntry) {
  if (entry.is_dir) return Folder
  if (isVideo(entry)) return FilePlay
  if (isAudio(entry)) return FileHeadphone
  if (isImage(entry)) return FileImage
  if (isPDF(entry) || (entry.mime ?? '').startsWith('text/')) return FileText
  return File
}

function iconClass(entry: FileEntry): string {
  if (entry.is_dir) return 'text-amber-300/80'
  if (isVideo(entry)) return 'text-cyan-300/80'
  if (isAudio(entry)) return 'text-indigo-300/80'
  if (isImage(entry)) return 'text-emerald-300/80'
  if (isPDF(entry)) return 'text-rose-300/80'
  return 'text-slate-500'
}

async function confirmDelete(): Promise<void> {
  const target = pendingDelete.value
  if (!target) return
  deleting.value = true
  try {
    await api.deleteFile(target.path, target.is_dir)
    pendingDelete.value = null
    push('已删除', 'success')
    await load(path.value)
  } catch (err) {
    push(errorMessage(err), 'error')
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <div class="space-y-5">
    <header class="flex flex-wrap items-end justify-between gap-3 pt-2 sm:pt-4">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-white">文件浏览</h1>
        <p class="mt-1 text-sm text-slate-400">查看、预览或清理 NAS 下载目录中的文件。</p>
      </div>
      <button type="button" class="btn-ghost px-3 py-2 text-xs" :disabled="loading" @click="load(path)">
        <RefreshCw :size="14" :class="{ 'animate-spin': loading }" />
        刷新
      </button>
    </header>

    <div class="glass-card overflow-hidden">
      <div class="flex flex-wrap items-center gap-1 border-b border-white/5 px-3 py-2.5">
        <button
          type="button"
          class="flex items-center gap-1 rounded-md px-2 py-1 text-xs text-slate-400 transition hover:bg-white/5 hover:text-white"
          @click="load('')"
        >
          <FolderOpen :size="14" />
          根目录
        </button>
        <template v-for="crumb in crumbs" :key="crumb.path">
          <ChevronRight :size="12" class="shrink-0 text-slate-600" />
          <button
            type="button"
            class="max-w-[40vw] truncate rounded-md px-2 py-1 text-xs text-slate-400 transition hover:bg-white/5 hover:text-white sm:max-w-xs"
            @click="load(crumb.path)"
          >
            {{ crumb.name }}
          </button>
        </template>
      </div>

      <p
        v-if="error"
        class="border-b border-rose-300/10 bg-rose-500/10 px-4 py-2.5 text-xs text-rose-200"
      >
        {{ error }}
      </p>

      <div v-if="loading" class="divide-y divide-white/[0.04]">
        <div v-for="n in 5" :key="n" class="flex items-center gap-3 px-3 py-3">
          <div class="h-5 w-5 shrink-0 animate-pulse rounded bg-white/[0.06]" />
          <div class="h-3.5 w-1/2 animate-pulse rounded bg-white/[0.06]" />
        </div>
      </div>

      <div v-else-if="listing && listing.entries.length > 0">
        <div
          v-for="entry in listing.entries"
          :key="entry.path"
          class="flex items-center gap-3 border-b border-white/[0.04] px-3 py-2.5 transition last:border-0 hover:bg-white/[0.025]"
        >
          <component
            :is="iconFor(entry)"
            :size="18"
            :stroke-width="1.8"
            class="shrink-0"
            :class="iconClass(entry)"
          />
          <button type="button" class="min-w-0 flex-1 text-left" @click="openEntry(entry)">
            <p
              class="truncate text-sm"
              :class="entry.is_dir ? 'text-slate-100 hover:text-cyan-200' : 'text-slate-300'"
            >
              {{ entry.name }}
            </p>
            <p class="mt-0.5 text-[11px] text-slate-600 sm:hidden">
              {{ entry.is_dir ? '文件夹' : formatBytes(entry.size) }}
            </p>
          </button>
          <span class="hidden w-20 shrink-0 text-right text-[11px] text-slate-500 sm:block">
            {{ entry.is_dir ? '—' : formatBytes(entry.size) }}
          </span>
          <span class="hidden w-24 shrink-0 text-right text-[11px] text-slate-500 md:block">
            {{ formatDate(entry.mtime) }}
          </span>
          <div class="flex shrink-0 items-center gap-1">
            <button
              v-if="isPreviewable(entry)"
              type="button"
              class="icon-btn h-8 w-8"
              :title="isMedia(entry) ? '播放链接' : '预览'"
              @click="openPreview(entry)"
            >
              <Eye :size="14" />
            </button>
            <a
              v-if="!entry.is_dir"
              :href="api.contentUrl(entry.path)"
              class="icon-btn h-8 w-8"
              title="下载"
              download
            >
              <Download :size="14" />
            </a>
            <button
              type="button"
              class="icon-btn h-8 w-8 hover:border-rose-300/30 hover:bg-rose-500/10 hover:text-rose-300"
              title="删除"
              @click="pendingDelete = entry"
            >
              <Trash2 :size="14" />
            </button>
          </div>
        </div>
      </div>

      <div
        v-else-if="listing"
        class="flex flex-col items-center justify-center gap-3 px-6 py-16 text-center"
      >
        <span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-white/[0.04] text-slate-600">
          <FolderOpen :size="22" />
        </span>
        <p class="text-sm text-slate-400">这个目录还是空的</p>
        <p class="text-xs text-slate-600">下载完成的视频会出现在这里。</p>
      </div>
    </div>

    <PreviewDialog v-if="preview" :entry="preview" @close="preview = null" />
    <MediaLinkDialog v-if="mediaLink" :entry="mediaLink" @close="mediaLink = null" />
    <ConfirmDialog
      v-if="pendingDelete"
      title="删除文件"
      :message="deleteMessage"
      :busy="deleting"
      @cancel="pendingDelete = null"
      @confirm="confirmDelete"
    />
  </div>
</template>
