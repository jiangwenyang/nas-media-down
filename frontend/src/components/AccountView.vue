<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { Crown, LogOut, QrCode } from 'lucide-vue-next'
import { api, errorMessage } from '../api'
import { useToast } from '../composables/useToast'
import type { BilibiliStatus } from '../types'
import { formatDate } from '../utils/format'
import QrLoginDialog from './QrLoginDialog.vue'

const { push } = useToast()

const status = ref<BilibiliStatus | null>(null)
const loading = ref(true)
const error = ref('')
const qrOpen = ref(false)
const busy = ref(false)

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    status.value = await api.bilibiliStatus()
  } catch (err) {
    error.value = errorMessage(err)
  } finally {
    loading.value = false
  }
}

onMounted(load)

async function onLoginSuccess(): Promise<void> {
  qrOpen.value = false
  await load()
  push('哔哩哔哩登录成功', 'success')
}

async function logout(): Promise<void> {
  if (busy.value) return
  busy.value = true
  try {
    await api.bilibiliLogout()
    status.value = { logged_in: false, uname: null, vip: false, expires_at: null }
    push('已退出哔哩哔哩登录', 'info')
  } catch (err) {
    push(errorMessage(err), 'error')
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="space-y-5">
    <header class="pt-2 sm:pt-4">
      <h1 class="text-2xl font-semibold tracking-tight text-white">账号</h1>
      <p class="mt-1 text-sm text-slate-400">扫码登录哔哩哔哩，可下载大会员专属内容。</p>
    </header>

    <article class="glass-card p-5">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="flex items-center gap-3">
          <span
            class="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-sky-400/20 to-pink-400/20 text-white ring-1 ring-white/10"
          >
            <span class="text-lg font-black">B</span>
          </span>
          <div>
            <h2 class="text-base font-semibold text-white">哔哩哔哩</h2>
            <p class="mt-0.5 text-xs text-slate-400">bilibili.com / b23.tv</p>
          </div>
        </div>

        <span
          v-if="status?.logged_in"
          class="status-pill border-emerald-300/30 bg-emerald-400/10 text-emerald-200"
        >
          <span class="h-1.5 w-1.5 rounded-full bg-emerald-300" />
          已登录
        </span>
        <span v-else class="status-pill border-slate-400/20 bg-slate-500/10 text-slate-400">
          未登录
        </span>
      </div>

      <div v-if="loading" class="mt-5 h-20 animate-pulse rounded-xl bg-white/[0.04]" />

      <div v-else-if="status?.logged_in" class="mt-5 space-y-3">
        <div class="rounded-xl border border-white/5 bg-white/[0.02] px-4 py-3">
          <p class="text-sm font-medium text-slate-100">
            {{ status.uname || '已保存登录信息' }}
          </p>
          <p class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-slate-500">
            <span
              v-if="status.vip"
              class="inline-flex items-center gap-1 rounded-full bg-amber-400/10 px-2 py-0.5 text-amber-200"
            >
              <Crown :size="12" />
              大会员
            </span>
            <span v-else>普通账号</span>
            <span v-if="status.expires_at">· 登录有效期至 {{ formatDate(status.expires_at) }}</span>
          </p>
        </div>
        <button type="button" class="btn-ghost" :disabled="busy" @click="logout">
          <LogOut :size="15" />
          退出登录
        </button>
      </div>

      <div
        v-else
        class="mt-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <p class="max-w-md text-xs leading-relaxed text-slate-400">
          用哔哩哔哩 App 扫码登录后，下载会员专属清晰度时会自动携带登录 Cookie。
        </p>
        <button type="button" class="btn-primary shrink-0" @click="qrOpen = true">
          <QrCode :size="16" />
          扫码登录
        </button>
      </div>

      <p
        v-if="error"
        class="mt-3 flex flex-wrap items-center gap-2 rounded-lg border border-rose-300/20 bg-rose-500/10 px-3 py-2 text-xs text-rose-200"
      >
        {{ error }}
        <button type="button" class="underline underline-offset-2" @click="load">重试</button>
      </p>
    </article>

    <div class="glass-card p-4 text-xs leading-relaxed text-slate-500">
      <p>
        登录 Cookie 仅保存在 NAS 的
        <code class="text-slate-300">DATA_DIR/bilibili-cookies.txt</code>（权限 600），不会上传到其他服务。
      </p>
      <p class="mt-1">会员内容下载请遵守哔哩哔哩服务条款；登录过期后重新扫码即可。</p>
    </div>

    <QrLoginDialog v-if="qrOpen" @close="qrOpen = false" @success="onLoginSuccess" />
  </div>
</template>
