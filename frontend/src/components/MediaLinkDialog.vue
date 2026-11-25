<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import {
  Check,
  Copy,
  Download,
  FileHeadphone,
  FilePlay,
  LoaderCircle,
  RotateCw,
  Smartphone,
  X,
} from 'lucide-vue-next'
import { api, errorMessage } from '../api'
import { useToast } from '../composables/useToast'
import type { FileEntry, ShareLink } from '../types'
import { copyText } from '../utils/clipboard'
import { formatBytes, formatDate } from '../utils/format'

const props = defineProps<{
  entry: FileEntry
}>()

const emit = defineEmits<{
  close: []
}>()

const { push } = useToast()

const share = ref<ShareLink | null>(null)
const loading = ref(true)
const error = ref('')
const copied = ref(false)

const isVideo = computed(
  () =>
    (props.entry.mime ?? '').startsWith('video/') ||
    /\.(mkv|mp4|m4v|mov|webm|avi|flv|ts|wmv|3gp)$/i.test(props.entry.name),
)

const absoluteUrl = computed(() => {
  if (!share.value) return ''
  try {
    return new URL(api.shareUrl(share.value.token), window.location.href).toString()
  } catch {
    return ''
  }
})

const vidhubUrl = computed(() =>
  absoluteUrl.value
    ? `open-vidhub://x-callback-url/open?url=${encodeURIComponent(absoluteUrl.value)}`
    : '',
)

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  copied.value = false
  try {
    share.value = await api.createShareLink(props.entry.path)
  } catch (err) {
    error.value = errorMessage(err)
    share.value = null
  } finally {
    loading.value = false
  }
}

async function copy(): Promise<void> {
  if (!absoluteUrl.value) return
  const ok = await copyText(absoluteUrl.value)
  if (ok) {
    copied.value = true
    push('链接已复制', 'success')
  } else {
    push('复制失败，请手动选择链接复制', 'error')
  }
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
      class="animate-overlay-in fixed inset-0 z-[65] flex items-end justify-center bg-slate-950/80 p-3 backdrop-blur-sm sm:items-center sm:p-6"
      @click.self="emit('close')"
    >
      <div class="animate-float-in glass-card w-full max-w-md overflow-hidden">
        <header class="flex items-start justify-between gap-3 border-b border-white/5 px-5 py-4">
          <div class="flex min-w-0 items-center gap-3">
            <span
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white/[0.04] text-cyan-300/90"
            >
              <component :is="isVideo ? FilePlay : FileHeadphone" :size="20" />
            </span>
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-slate-100" :title="entry.name">
                {{ entry.name }}
              </p>
              <p class="mt-0.5 text-[11px] text-slate-500">
                {{ formatBytes(entry.size) }}
                <template v-if="share">
                  · 链接有效期至 {{ formatDate(share.expires_at) }}
                </template>
              </p>
            </div>
          </div>
          <button type="button" class="icon-btn shrink-0" aria-label="关闭" @click="emit('close')">
            <X :size="15" />
          </button>
        </header>

        <div class="space-y-3 p-5">
          <div
            v-if="loading"
            class="flex items-center justify-center gap-2 py-6 text-sm text-slate-400"
          >
            <LoaderCircle :size="18" class="animate-spin" />
            正在生成播放链接…
          </div>

          <template v-else-if="error">
            <p
              class="rounded-xl border border-rose-300/20 bg-rose-500/10 px-3.5 py-2.5 text-xs leading-relaxed text-rose-200"
            >
              {{ error }}
            </p>
            <button type="button" class="btn-ghost w-full" @click="load">
              <RotateCw :size="15" />
              重试
            </button>
          </template>

          <template v-else>
            <a :href="vidhubUrl" class="btn-primary w-full">
              <Smartphone :size="16" />
              用 VidHub 打开
            </a>

            <button type="button" class="btn-ghost w-full" @click="copy">
              <Check v-if="copied" :size="16" />
              <Copy v-else :size="16" />
              {{ copied ? '链接已复制' : '复制链接' }}
            </button>

            <a :href="api.contentUrl(entry.path)" class="btn-ghost w-full" download>
              <Download :size="16" />
              下载文件
            </a>

            <p class="text-center text-[11px] leading-relaxed text-slate-500">
              MKV 等格式由 VidHub 解码；链接 6 小时内有效。VidHub 仅支持 iPhone / iPad，未安装时请复制链接。
            </p>
          </template>
        </div>
      </div>
    </div>
  </Teleport>
</template>
