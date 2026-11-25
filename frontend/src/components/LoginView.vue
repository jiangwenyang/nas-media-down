<script setup lang="ts">
import { ref } from 'vue'
import { Download, Eye, EyeOff, LockKeyhole } from 'lucide-vue-next'
import { errorMessage } from '../api'
import { useAuth } from '../composables/useAuth'

const { login } = useAuth()

const password = ref('')
const showPassword = ref(false)
const submitting = ref(false)
const error = ref('')

async function submit(): Promise<void> {
  if (submitting.value) return
  const value = password.value.trim()
  if (!value) {
    error.value = '请输入访问密码'
    return
  }
  submitting.value = true
  error.value = ''
  try {
    await login(value)
  } catch (err) {
    error.value = errorMessage(err)
    password.value = ''
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="relative flex min-h-screen items-center justify-center px-4 py-12">
    <div
      class="pointer-events-none absolute top-1/4 left-1/2 h-72 w-72 -translate-x-1/2 rounded-full bg-cyan-400/10 blur-3xl"
    />

    <div class="relative w-full max-w-sm">
      <div class="mb-8 flex flex-col items-center text-center">
        <span
          class="mb-4 flex h-14 w-14 items-center justify-center rounded-3xl bg-gradient-to-br from-cyan-300 via-sky-400 to-indigo-400 text-slate-950 shadow-xl shadow-cyan-500/25"
        >
          <Download :size="26" :stroke-width="2.4" />
        </span>
        <h1 class="text-2xl font-semibold tracking-tight text-white">媒体下载</h1>
        <p class="mt-1.5 text-sm text-slate-400">登录后即可探测并下载视频</p>
      </div>

      <form class="glass-card animate-float-in p-6 sm:p-7" @submit.prevent="submit">
        <label for="password" class="mb-2 block text-xs font-medium tracking-wide text-slate-400">
          访问密码
        </label>
        <div class="relative">
          <LockKeyhole
            :size="16"
            class="pointer-events-none absolute top-1/2 left-3.5 -translate-y-1/2 text-slate-500"
          />
          <input
            id="password"
            v-model="password"
            :type="showPassword ? 'text' : 'password'"
            autocomplete="current-password"
            autofocus
            placeholder="请输入 ACCESS_PASSWORD"
            class="field pr-11 pl-10"
            :disabled="submitting"
          />
          <button
            type="button"
            class="absolute top-1/2 right-2.5 -translate-y-1/2 rounded-md p-1.5 text-slate-500 transition hover:text-slate-200 focus-visible:ring-2 focus-visible:ring-cyan-300/60 focus-visible:outline-none"
            :aria-label="showPassword ? '隐藏密码' : '显示密码'"
            @click="showPassword = !showPassword"
          >
            <component :is="showPassword ? EyeOff : Eye" :size="16" />
          </button>
        </div>

        <p
          v-if="error"
          class="mt-3 rounded-lg border border-rose-300/20 bg-rose-500/10 px-3 py-2 text-xs text-rose-200"
        >
          {{ error }}
        </p>

        <button type="submit" class="btn-primary mt-5 w-full" :disabled="submitting">
          <span
            v-if="submitting"
            class="h-4 w-4 animate-spin rounded-full border-2 border-slate-900/30 border-t-slate-900"
          />
          {{ submitting ? '正在验证…' : '进入控制台' }}
        </button>

        <p class="mt-4 text-center text-[11px] leading-relaxed text-slate-500">
          访问密码由 NAS 上的环境变量 <code class="text-slate-400">ACCESS_PASSWORD</code> 配置
        </p>
      </form>
    </div>
  </div>
</template>
