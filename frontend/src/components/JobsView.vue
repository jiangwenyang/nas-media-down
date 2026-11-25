<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Inbox, RefreshCw } from 'lucide-vue-next'
import { useJobs } from '../composables/useJobs'
import JobCard from './JobCard.vue'

type Filter = 'all' | 'active' | 'done' | 'failed'

const FILTERS: Array<{ id: Filter; label: string }> = [
  { id: 'all', label: '全部' },
  { id: 'active', label: '进行中' },
  { id: 'done', label: '已完成' },
  { id: 'failed', label: '失败' },
]

const { jobs, loading, error, refresh } = useJobs()
const filter = ref<Filter>('all')

onMounted(() => {
  void refresh()
})

const filtered = computed(() => {
  switch (filter.value) {
    case 'active':
      return jobs.value.filter((job) => job.status === 'queued' || job.status === 'running')
    case 'done':
      return jobs.value.filter((job) => job.status === 'completed' || job.status === 'partial')
    case 'failed':
      return jobs.value.filter((job) =>
        ['failed', 'cancelled', 'interrupted'].includes(job.status),
      )
    default:
      return jobs.value
  }
})

const emptyText = computed(() => {
  switch (filter.value) {
    case 'active':
      return '当前没有进行中的下载'
    case 'done':
      return '还没有已完成的任务'
    case 'failed':
      return '没有失败或中断的任务'
    default:
      return '下载任务会显示在这里'
  }
})
</script>

<template>
  <div class="space-y-5">
    <header class="flex flex-wrap items-end justify-between gap-3 pt-2 sm:pt-4">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-white">任务历史</h1>
        <p class="mt-1 text-sm text-slate-400">共 {{ jobs.length }} 条记录，活动任务每秒刷新。</p>
      </div>
      <button type="button" class="btn-ghost px-3 py-2 text-xs" :disabled="loading" @click="refresh">
        <RefreshCw :size="14" :class="{ 'animate-spin': loading }" />
        刷新
      </button>
    </header>

    <div class="flex flex-wrap gap-1.5">
      <button
        v-for="item in FILTERS"
        :key="item.id"
        type="button"
        class="rounded-full border px-3.5 py-1.5 text-xs font-medium transition"
        :class="
          filter === item.id
            ? 'border-cyan-300/40 bg-cyan-300/10 text-cyan-100'
            : 'border-white/10 bg-white/[0.02] text-slate-400 hover:border-white/20 hover:text-slate-200'
        "
        @click="filter = item.id"
      >
        {{ item.label }}
      </button>
    </div>

    <p
      v-if="error"
      class="rounded-xl border border-rose-300/20 bg-rose-500/10 px-3.5 py-2.5 text-xs text-rose-200"
    >
      {{ error }}
    </p>

    <div v-if="filtered.length > 0" class="space-y-3">
      <JobCard v-for="job in filtered" :key="job.id" :job="job" />
    </div>

    <div
      v-else
      class="glass-card flex flex-col items-center justify-center gap-3 px-6 py-16 text-center"
    >
      <span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-white/[0.04] text-slate-600">
        <Inbox :size="22" />
      </span>
      <p class="text-sm text-slate-400">{{ emptyText }}</p>
      <p class="text-xs text-slate-600">回到「下载」页粘贴网址即可创建任务。</p>
    </div>
  </div>
</template>
