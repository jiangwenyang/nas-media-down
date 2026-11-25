<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import type { Component } from 'vue'
import { Download, FolderOpen, ListChecks, LogOut } from 'lucide-vue-next'
import { useAuth } from './composables/useAuth'
import { useJobs } from './composables/useJobs'
import LoginView from './components/LoginView.vue'
import DownloadView from './components/DownloadView.vue'
import JobsView from './components/JobsView.vue'
import FileBrowser from './components/FileBrowser.vue'
import ToastHost from './components/ToastHost.vue'

type Tab = 'download' | 'jobs' | 'files'

const tabs: Array<{ id: Tab; label: string; icon: Component }> = [
  { id: 'download', label: '下载', icon: Download },
  { id: 'jobs', label: '任务', icon: ListChecks },
  { id: 'files', label: '文件', icon: FolderOpen },
]

const activeTab = ref<Tab>('download')
const { authenticated, check, logout } = useAuth()
const { start, stop } = useJobs()

onMounted(() => {
  void check()
})

watch(
  authenticated,
  (value) => {
    if (value) start()
    else stop()
  },
  { immediate: true },
)

async function handleLogout(): Promise<void> {
  stop()
  await logout()
}
</script>

<template>
  <div class="relative min-h-screen">
    <ToastHost />

    <div v-if="authenticated === null" class="flex min-h-screen items-center justify-center">
      <div class="h-10 w-10 animate-spin rounded-full border-2 border-white/10 border-t-cyan-300" />
    </div>

    <LoginView v-else-if="!authenticated" />

    <template v-else>
      <header class="sticky top-0 z-20 border-b border-white/5 bg-[#070b12]/85 backdrop-blur-xl">
        <div class="mx-auto flex h-16 max-w-5xl items-center justify-between gap-3 px-4 sm:px-6">
          <div class="flex items-center gap-3">
            <span
              class="flex h-10 w-10 items-center justify-center rounded-2xl bg-gradient-to-br from-cyan-300 via-sky-400 to-indigo-400 text-slate-950 shadow-lg shadow-cyan-500/20"
            >
              <Download :size="20" :stroke-width="2.4" />
            </span>
            <div class="leading-tight">
              <p class="text-sm font-semibold tracking-tight text-white">媒体下载</p>
              <p class="text-[10px] tracking-[0.16em] text-slate-500">NAS MEDIA DOWN</p>
            </div>
          </div>

          <nav class="flex items-center gap-1 rounded-xl border border-white/10 bg-white/[0.03] p-1">
            <button
              v-for="tab in tabs"
              :key="tab.id"
              type="button"
              class="flex items-center gap-1.5 rounded-lg px-2.5 py-2 text-xs font-medium transition sm:px-3 sm:text-sm"
              :class="
                activeTab === tab.id
                  ? 'bg-white/10 text-white shadow-[0_1px_0_rgba(255,255,255,0.08)_inset]'
                  : 'text-slate-400 hover:text-slate-200'
              "
              @click="activeTab = tab.id"
            >
              <component :is="tab.icon" :size="16" />
              <span>{{ tab.label }}</span>
            </button>
          </nav>

          <button
            type="button"
            class="icon-btn"
            title="退出登录"
            aria-label="退出登录"
            @click="handleLogout"
          >
            <LogOut :size="16" />
          </button>
        </div>
      </header>

      <main class="mx-auto max-w-5xl px-4 py-6 sm:px-6 sm:py-10">
        <div :key="activeTab" class="animate-float-in">
          <DownloadView v-if="activeTab === 'download'" @open-jobs="activeTab = 'jobs'" />
          <JobsView v-else-if="activeTab === 'jobs'" />
          <FileBrowser v-else />
        </div>
      </main>

      <footer class="pb-8 text-center text-[11px] text-slate-600">
        文件保存在 NAS 映射目录 · 请勿在公网无保护暴露本服务
      </footer>
    </template>
  </div>
</template>
