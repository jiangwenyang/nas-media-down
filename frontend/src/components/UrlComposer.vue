<script setup lang="ts">
import { ref } from 'vue'
import { ClipboardPaste, Link2, LoaderCircle, Search } from 'lucide-vue-next'
import { useToast } from '../composables/useToast'

const props = defineProps<{
  modelValue: string
  loading: boolean
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
  submit: []
}>()

const { push } = useToast()
const inputRef = ref<HTMLInputElement | null>(null)

async function pasteFromClipboard(): Promise<void> {
  try {
    const text = await navigator.clipboard.readText()
    if (text.trim()) {
      emit('update:modelValue', text.trim())
    }
    inputRef.value?.focus()
  } catch {
    push('浏览器未授权读取剪贴板，请手动粘贴', 'info')
    inputRef.value?.focus()
  }
}

function submit(): void {
  if (props.loading) return
  if (!props.modelValue.trim()) {
    push('请先粘贴视频网址', 'info')
    inputRef.value?.focus()
    return
  }
  emit('submit')
}
</script>

<template>
  <form class="glass-card p-4 sm:p-5" @submit.prevent="submit">
    <div class="flex flex-col gap-3 sm:flex-row">
      <div class="relative flex-1">
        <Link2
          :size="17"
          class="pointer-events-none absolute top-1/2 left-3.5 -translate-y-1/2 text-slate-500"
        />
        <input
          ref="inputRef"
          :value="modelValue"
          type="url"
          inputmode="url"
          spellcheck="false"
          autocomplete="off"
          placeholder="粘贴视频或播放列表网址…"
          class="field py-3.5 pr-24 pl-10 sm:py-4"
          :disabled="loading"
          @input="emit('update:modelValue', ($event.target as HTMLInputElement).value)"
        />
        <button
          type="button"
          class="absolute top-1/2 right-2.5 flex -translate-y-1/2 items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-medium text-slate-400 transition hover:bg-white/5 hover:text-slate-100 focus-visible:ring-2 focus-visible:ring-cyan-300/60 focus-visible:outline-none"
          :disabled="loading"
          @click="pasteFromClipboard"
        >
          <ClipboardPaste :size="14" />
          粘贴
        </button>
      </div>

      <button type="submit" class="btn-primary px-5 py-3.5 sm:py-4" :disabled="loading">
        <LoaderCircle v-if="loading" :size="17" class="animate-spin" />
        <Search v-else :size="17" />
        {{ loading ? '探测中…' : '探测' }}
      </button>
    </div>
    <p class="mt-3 text-[11px] leading-relaxed text-slate-500">
      支持 yt-dlp 可解析的站点（YouTube、Bilibili 等），也可直接粘贴 m3u8 链接；播放列表会弹窗供勾选。
    </p>
  </form>
</template>
