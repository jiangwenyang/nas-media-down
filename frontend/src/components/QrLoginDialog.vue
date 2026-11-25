<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import QRCode from 'qrcode'
import { LoaderCircle, QrCode, RefreshCw, Smartphone, X } from 'lucide-vue-next'
import { api, errorMessage } from '../api'
import type { BilibiliPoll } from '../types'

const emit = defineEmits<{
  close: []
  success: [status: BilibiliPoll]
}>()

const image = ref('')
const hint = ref('正在生成二维码…')
const error = ref('')
const loading = ref(true)
const expired = ref(false)
const scanned = ref(false)

let key = ''
let timer: number | undefined
let closed = false
let generation = 0

async function generate(): Promise<void> {
  const current = ++generation
  if (timer !== undefined) {
    window.clearTimeout(timer)
    timer = undefined
  }
  loading.value = true
  error.value = ''
  expired.value = false
  scanned.value = false
  hint.value = '正在生成二维码…'

  try {
    const data = await api.bilibiliQrCode()
    if (current !== generation) return
    key = data.key
    image.value = await QRCode.toDataURL(data.url, {
      margin: 1,
      width: 280,
      errorCorrectionLevel: 'M',
      color: { dark: '#0b1220', light: '#ffffff' },
    })
    if (current !== generation) return
    hint.value = '请使用哔哩哔哩 App 扫码'
    loading.value = false
    schedule()
  } catch (err) {
    if (current !== generation) return
    error.value = errorMessage(err)
    loading.value = false
  }
}

function schedule(): void {
  if (closed) return
  timer = window.setTimeout(poll, 2000)
}

async function poll(): Promise<void> {
  if (closed) return
  const current = generation
  try {
    const data = await api.bilibiliQrPoll(key)
    if (current !== generation) return
    if (data.code === 0) {
      hint.value = '登录成功'
      emit('success', data)
      return
    }
    if (data.code === 86038) {
      expired.value = true
      hint.value = '二维码已过期'
      return
    }
    scanned.value = data.code === 86090
    hint.value = data.status
    schedule()
  } catch (err) {
    if (current !== generation) return
    error.value = errorMessage(err)
  }
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Escape') emit('close')
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
  document.body.style.overflow = 'hidden'
  void generate()
})

onUnmounted(() => {
  closed = true
  generation += 1
  if (timer !== undefined) window.clearTimeout(timer)
  window.removeEventListener('keydown', onKeydown)
  document.body.style.overflow = ''
})
</script>

<template>
  <Teleport to="body">
    <div
      class="animate-overlay-in fixed inset-0 z-[75] flex items-center justify-center bg-slate-950/80 px-4 backdrop-blur-sm"
      @click.self="emit('close')"
    >
      <div class="animate-float-in glass-card w-full max-w-sm p-5 sm:p-6">
        <header class="flex items-start justify-between gap-3">
          <div>
            <h2 class="text-base font-semibold text-white">哔哩哔哩扫码登录</h2>
            <p class="mt-1 text-xs text-slate-400">使用哔哩哔哩 App 扫描下方二维码</p>
          </div>
          <button type="button" class="icon-btn shrink-0" aria-label="关闭" @click="emit('close')">
            <X :size="16" />
          </button>
        </header>

        <div class="mt-5 flex justify-center">
          <div
            class="flex h-[300px] w-[300px] items-center justify-center rounded-2xl bg-white p-3 shadow-inner"
          >
            <LoaderCircle v-if="loading" :size="32" class="animate-spin text-slate-400" />
            <div v-else-if="expired" class="flex flex-col items-center gap-2 text-slate-500">
              <QrCode :size="40" />
              <span class="text-xs">二维码已过期</span>
            </div>
            <img
              v-else-if="image"
              :src="image"
              alt="哔哩哔哩登录二维码"
              class="h-full w-full rounded-lg"
            />
            <div v-else class="flex flex-col items-center gap-2 text-slate-500">
              <QrCode :size="40" />
              <span class="text-xs">二维码不可用</span>
            </div>
          </div>
        </div>

        <p class="mt-4 flex items-center justify-center gap-2 text-center text-sm text-slate-300">
          <Smartphone v-if="scanned" :size="15" class="text-cyan-300" />
          {{ hint }}
        </p>

        <p
          v-if="error"
          class="mt-3 rounded-lg border border-rose-300/20 bg-rose-500/10 px-3 py-2 text-xs leading-relaxed text-rose-200"
        >
          {{ error }}
        </p>

        <button
          v-if="expired || error"
          type="button"
          class="btn-ghost mt-4 w-full"
          :disabled="loading"
          @click="generate"
        >
          <RefreshCw :size="15" />
          重新获取二维码
        </button>

        <p class="mt-4 text-center text-[11px] leading-relaxed text-slate-500">
          扫码后请在手机上确认登录，二维码几分钟内有效。
        </p>
      </div>
    </div>
  </Teleport>
</template>
