<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { BellRing, CheckCircle2, Clapperboard, Inbox, RefreshCw, Tv } from 'lucide-vue-next'
import { api, errorMessage } from '../api'
import { useToast } from '../composables/useToast'
import type { BangumiFollowItem, BangumiSubscription } from '../types'
import { formatDate } from '../utils/format'
import ConfirmDialog from './ConfirmDialog.vue'
import BangumiEpisodeDialog from './BangumiEpisodeDialog.vue'

const emit = defineEmits<{
  'open-account': []
}>()

const { push } = useToast()

const MEDIA_OPTIONS: Array<{ id: 1 | 2; label: string }> = [
  { id: 1, label: '番剧' },
  { id: 2, label: '追剧' },
]

const loggedIn = ref(false)
const loginChecked = ref(false)
const mediaType = ref<1 | 2>(1)
const items = ref<BangumiFollowItem[]>([])
const page = ref(1)
const total = ref(0)
const hasMore = ref(false)
const loadingFollow = ref(false)
const followError = ref('')
const subscriptions = ref<BangumiSubscription[]>([])
const loadingSubs = ref(false)
const subsError = ref('')
const busy = ref<string | null>(null)
const confirmTarget = ref<BangumiSubscription | null>(null)
const episodeTarget = ref<{ seasonId: number; title: string; subscribed: boolean } | null>(null)

const activeSubs = computed(() => subscriptions.value)
const canLoadMore = computed(() => hasMore.value && !loadingFollow.value)

/** 判断指定操作是否正在进行，用于按钮文案与禁用状态。 */
function isBusy(key: string): boolean {
  return busy.value === key
}

/** 读取哔哩哔哩登录状态，决定是否展示关注列表。 */
async function loadStatus(): Promise<void> {
  try {
    const status = await api.bilibiliStatus()
    loggedIn.value = status.logged_in
  } catch {
    loggedIn.value = false
  } finally {
    loginChecked.value = true
  }
}

/** 加载关注列表；reset 为 true 时从第一页重新加载，否则追加下一页。 */
async function loadFollow(reset = false): Promise<void> {
  if (loadingFollow.value || !loggedIn.value) return
  loadingFollow.value = true
  followError.value = ''
  const target = reset ? 1 : page.value + 1
  try {
    const data = await api.bangumiFollow(mediaType.value, target)
    items.value = reset ? data.items : [...items.value, ...data.items]
    page.value = data.page
    total.value = data.total
    hasMore.value = data.has_more
  } catch (error) {
    followError.value = errorMessage(error)
  } finally {
    loadingFollow.value = false
  }
}

/** 加载追更订阅及下载统计。 */
async function loadSubscriptions(): Promise<void> {
  loadingSubs.value = true
  subsError.value = ''
  try {
    const data = await api.bangumiSubscriptions()
    subscriptions.value = data.subscriptions
  } catch (error) {
    subsError.value = errorMessage(error)
  } finally {
    loadingSubs.value = false
  }
}

onMounted(async () => {
  await loadStatus()
  void loadSubscriptions()
  if (loggedIn.value) await loadFollow(true)
})

watch(mediaType, () => {
  items.value = []
  page.value = 1
  hasMore.value = false
  void loadFollow(true)
})

/**
 * 订阅一部剧。
 *
 * @param item 关注列表条目
 * @param mode watch 仅跟踪后续更新；all 同时下载当前已发布剧集
 */
async function subscribe(item: BangumiFollowItem, mode: 'watch' | 'all'): Promise<void> {
  const key = `${mode}-${item.season_id}`
  if (busy.value) return
  busy.value = key
  try {
    const result = await api.bangumiSubscribe({
      season_id: item.season_id,
      media_type: mediaType.value,
      mode,
    })
    item.subscribed = true
    item.subscription_id = result.subscription?.id ?? null
    if (mode === 'all') {
      if (result.job_count > 0) {
        push(`已加入下载队列：${result.job_count} 个任务`, 'success')
      } else if (result.error) {
        push(result.error, 'error')
      } else {
        push('没有可下载的剧集', 'info')
      }
    } else {
      push(`已开始追更《${item.title}》`, 'success')
    }
    await loadSubscriptions()
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    busy.value = null
  }
}

/** 打开选集下载弹窗。 */
function openEpisodeDialog(seasonId: number, title: string, subscribed: boolean): void {
  if (busy.value) return
  episodeTarget.value = { seasonId, title, subscribed }
}

/** 下载弹窗中选中的剧集，并刷新追更统计。 */
async function downloadSelected(payload: { indices: number[] }): Promise<void> {
  const target = episodeTarget.value
  if (!target || busy.value) return
  busy.value = `episodes-${target.seasonId}`
  try {
    const result = await api.bangumiDownloadEpisodes({
      season_id: target.seasonId,
      episode_indices: payload.indices,
    })
    if (result.job_count > 0) {
      const skipped = result.skipped_count ?? 0
      push(
        skipped > 0
          ? `已加入下载队列：${result.episode_count} 集，跳过 ${skipped} 集已下载`
          : `已加入下载队列：${result.episode_count} 集`,
        'success',
      )
      episodeTarget.value = null
    } else if (result.error) {
      push(result.error, 'error')
    } else {
      push('没有可下载的剧集', 'info')
    }
    await loadSubscriptions()
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    busy.value = null
  }
}

/** 立即检查一部剧是否有新剧集。 */
async function checkNow(sub: BangumiSubscription): Promise<void> {  const key = `check-${sub.id}`
  if (busy.value) return
  busy.value = key
  try {
    const result = await api.bangumiCheckSubscription(sub.id)
    if (result.busy) {
      push('正在检查中，请稍后再试', 'info')
    } else if (result.error) {
      push(result.error, 'error')
    } else if (result.job_count > 0) {
      push(`发现 ${result.new_episodes} 集更新，已加入下载队列`, 'success')
    } else if (result.new_episodes > 0) {
      push(`发现 ${result.new_episodes} 集更新`, 'info')
    } else {
      push('暂无更新', 'info')
    }
    await loadSubscriptions()
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    busy.value = null
  }
}

/** 把该剧尚未下载的已发布剧集加入下载队列。 */
async function downloadAll(sub: BangumiSubscription): Promise<void> {
  const key = `all-${sub.id}`
  if (busy.value) return
  busy.value = key
  try {
    const result = await api.bangumiDownloadAll(sub.id)
    if (result.job_count > 0) {
      push(`已加入 ${result.job_count} 个下载任务，共 ${result.episode_count} 集`, 'success')
    } else if (result.error) {
      push(result.error, 'error')
    } else {
      push('没有需要下载的剧集', 'info')
    }
    await loadSubscriptions()
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    busy.value = null
  }
}

/** 切换订阅的自动下载开关。 */
async function toggleAuto(sub: BangumiSubscription): Promise<void> {
  const key = `auto-${sub.id}`
  if (busy.value) return
  busy.value = key
  try {
    const updated = await api.bangumiUpdateSubscription(sub.id, {
      auto_download: !sub.auto_download,
    })
    const index = subscriptions.value.findIndex((item) => item.id === sub.id)
    if (index >= 0) subscriptions.value[index] = updated
    push(updated.auto_download ? '已开启自动下载新集' : '已关闭自动下载', 'info')
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    busy.value = null
  }
}

/** 取消追更并刷新列表。 */
async function unsubscribe(): Promise<void> {
  const sub = confirmTarget.value
  if (!sub || busy.value) return
  busy.value = `del-${sub.id}`
  try {
    await api.bangumiDeleteSubscription(sub.id)
    confirmTarget.value = null
    const item = items.value.find((entry) => entry.season_id === sub.season_id)
    if (item) {
      item.subscribed = false
      item.subscription_id = null
    }
    push('已取消追更', 'success')
    await loadSubscriptions()
  } catch (error) {
    push(errorMessage(error), 'error')
  } finally {
    busy.value = null
  }
}

/** 计算已下载剧集占已发布剧集的百分比。 */
function progressPercent(sub: BangumiSubscription): number {
  if (!sub.episode_count) return 0
  return Math.min(100, Math.round((sub.done_count / sub.episode_count) * 100))
}

/** 滚动到指定订阅卡片，方便从关注列表跳转查看进度。 */
function focusSubscription(id: string | null): void {
  if (!id) return
  document.getElementById(`sub-${id}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
}
</script>

<template>
  <div class="space-y-6">
    <header class="pt-2 sm:pt-4">
      <h1 class="text-2xl font-semibold tracking-tight text-white sm:text-3xl">追番 · 追剧</h1>
      <p class="mt-2 text-sm leading-relaxed text-slate-400">
        读取哔哩哔哩关注列表，选择追更；有新剧集发布时自动下载，也可直接下载整季。
      </p>
    </header>

    <div v-if="!loginChecked" class="glass-card h-24 animate-pulse" />

    <template v-else>
      <article v-if="!loggedIn" class="glass-card flex flex-col gap-4 p-5 sm:flex-row sm:items-center">
        <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-sky-400/10 text-sky-200">
          <Tv :size="22" />
        </span>
        <div class="min-w-0 flex-1">
          <h2 class="text-base font-semibold text-white">需要先登录哔哩哔哩</h2>
          <p class="mt-1 text-xs leading-relaxed text-slate-400">
            关注列表需要账号登录才能读取。扫码登录后回到本页即可选择追番；已订阅的剧集仍会显示在这里。
          </p>
        </div>
        <button type="button" class="btn-primary shrink-0" @click="emit('open-account')">
          去账号页登录
        </button>
      </article>

      <section class="space-y-3">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="flex items-center gap-1.5 text-sm font-medium text-slate-300">
            <BellRing :size="15" class="text-cyan-300/80" />
            正在追更
            <span v-if="activeSubs.length" class="text-xs text-slate-500">共 {{ activeSubs.length }} 部</span>
          </h2>
          <button
            type="button"
            class="btn-ghost px-3 py-2 text-xs"
            :disabled="loadingSubs"
            @click="loadSubscriptions"
          >
            <RefreshCw :size="14" :class="{ 'animate-spin': loadingSubs }" />
            刷新
          </button>
        </div>

        <p
          v-if="subsError"
          class="rounded-xl border border-rose-300/20 bg-rose-500/10 px-3.5 py-2.5 text-xs text-rose-200"
        >
          {{ subsError }}
        </p>

        <div v-if="loadingSubs && !subscriptions.length" class="space-y-3">
          <div v-for="n in 2" :key="n" class="glass-card h-32 animate-pulse" />
        </div>

        <div
          v-else-if="!subscriptions.length"
          class="glass-card flex flex-col items-center justify-center gap-2 px-6 py-10 text-center"
        >
          <CheckCircle2 :size="22" class="text-slate-600" />
          <p class="text-sm text-slate-400">还没有追更的剧集</p>
          <p class="text-xs text-slate-600">
            {{ loggedIn ? '在下方关注列表里点「追更」，有新集时自动下载。' : '登录哔哩哔哩后可浏览关注列表并选择追番。' }}
          </p>
        </div>

        <div v-else class="space-y-3">
          <article
            v-for="sub in subscriptions"
            :id="`sub-${sub.id}`"
            :key="sub.id"
            class="glass-card p-4"
          >
            <div class="flex gap-3">
              <img
                v-if="sub.cover"
                :src="sub.cover"
                :alt="sub.title"
                referrerpolicy="no-referrer"
                loading="lazy"
                class="h-20 w-14 shrink-0 rounded-lg bg-slate-900 object-cover"
              />
              <span v-else class="h-20 w-14 shrink-0 rounded-lg bg-white/[0.04]" />

              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center gap-2">
                  <h3 class="min-w-0 truncate text-sm font-medium text-white">{{ sub.title }}</h3>
                  <span
                    class="status-pill border-cyan-300/30 bg-cyan-400/10 text-cyan-200"
                    :class="{ 'opacity-60': !sub.auto_download }"
                  >
                    {{ sub.auto_download ? '自动下载' : '仅手动' }}
                  </span>
                  <span v-if="sub.queued_count > 0" class="status-pill border-sky-300/30 bg-sky-400/10 text-sky-200">
                    {{ sub.queued_count }} 集排队中
                  </span>
                </div>
                <p class="mt-1 line-clamp-1 text-[11px] text-slate-500">
                  {{ sub.latest_title || '暂无剧集' }} · 已下载 {{ sub.done_count }}/{{ sub.episode_count }} 集
                  <template v-if="sub.failed_count"> · {{ sub.failed_count }} 集失败</template>
                </p>
                <p v-if="sub.last_error" class="mt-1 line-clamp-2 text-[11px] leading-relaxed text-rose-300/80">
                  {{ sub.last_error }}
                </p>
                <div class="mt-2">
                  <div class="progress-track">
                    <div class="progress-fill" :style="{ width: `${progressPercent(sub)}%` }" />
                  </div>
                  <p class="mt-1 text-[10px] text-slate-600">
                    上次检查：{{ sub.last_check_at ? formatDate(sub.last_check_at) : '尚未检查' }}
                  </p>
                </div>
                <div class="mt-2 flex flex-wrap gap-1.5">
                  <button
                    type="button"
                    class="btn-ghost px-2.5 py-1.5 text-xs"
                    :disabled="busy !== null"
                    @click="checkNow(sub)"
                  >
                    <RefreshCw :size="12" :class="{ 'animate-spin': isBusy(`check-${sub.id}`) }" />
                    立即检查
                  </button>
                  <button
                    type="button"
                    class="btn-ghost px-2.5 py-1.5 text-xs"
                    :disabled="busy !== null"
                    @click="openEpisodeDialog(sub.season_id, sub.title, true)"
                  >
                    选集下载
                  </button>
                  <button
                    type="button"
                    class="btn-ghost px-2.5 py-1.5 text-xs"
                    :disabled="busy !== null"
                    @click="downloadAll(sub)"
                  >
                    下载全部
                  </button>
                  <button
                    type="button"
                    class="btn-ghost px-2.5 py-1.5 text-xs"
                    :disabled="busy !== null"
                    @click="toggleAuto(sub)"
                  >
                    {{ sub.auto_download ? '关闭自动下载' : '开启自动下载' }}
                  </button>
                  <button
                    type="button"
                    class="btn-ghost px-2.5 py-1.5 text-xs text-rose-200"
                    :disabled="busy !== null"
                    @click="confirmTarget = sub"
                  >
                    取消追更
                  </button>
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>

      <section v-if="loggedIn" class="space-y-3">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 class="text-sm font-medium text-slate-300">我的关注</h2>
            <p class="mt-0.5 text-[11px] text-slate-500">共 {{ total }} 部，数据来自哔哩哔哩关注列表</p>
          </div>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="option in MEDIA_OPTIONS"
              :key="option.id"
              type="button"
              class="rounded-full border px-3.5 py-1.5 text-xs font-medium transition"
              :class="
                mediaType === option.id
                  ? 'border-cyan-300/40 bg-cyan-300/10 text-cyan-100'
                  : 'border-white/10 bg-white/[0.02] text-slate-400 hover:border-white/20 hover:text-slate-200'
              "
              @click="mediaType = option.id"
            >
              {{ option.label }}
            </button>
          </div>
        </div>

        <p
          v-if="followError"
          class="rounded-xl border border-rose-300/20 bg-rose-500/10 px-3.5 py-2.5 text-xs leading-relaxed text-rose-200"
        >
          {{ followError }}
        </p>

        <div v-if="loadingFollow && !items.length" class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          <div v-for="n in 8" :key="n" class="glass-card h-64 animate-pulse" />
        </div>

        <div
          v-else-if="!items.length && !followError"
          class="glass-card flex flex-col items-center justify-center gap-2 px-6 py-12 text-center"
        >
          <Inbox :size="22" class="text-slate-600" />
          <p class="text-sm text-slate-400">
            {{ mediaType === 1 ? '没有追番记录' : '没有追剧记录' }}
          </p>
        </div>

        <div v-else class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          <article
            v-for="item in items"
            :key="item.season_id"
            class="glass-card flex flex-col overflow-hidden"
          >
            <div class="relative aspect-[3/4] bg-white/[0.03]">
              <img
                v-if="item.cover"
                :src="item.cover"
                :alt="item.title"
                referrerpolicy="no-referrer"
                loading="lazy"
                class="h-full w-full object-cover"
              />
              <span
                class="absolute top-2 left-2 rounded-full border px-2 py-0.5 text-[10px] font-medium backdrop-blur"
                :class="
                  item.is_finish
                    ? 'border-slate-400/30 bg-slate-950/70 text-slate-300'
                    : 'border-cyan-300/40 bg-cyan-950/70 text-cyan-200'
                "
              >
                {{ item.is_finish ? '已完结' : '连载中' }}
              </span>
            </div>
            <div class="flex flex-1 flex-col gap-1.5 p-3">
              <h3 class="line-clamp-1 text-sm font-medium text-white" :title="item.title">
                {{ item.title }}
              </h3>
              <p class="line-clamp-1 text-[11px] text-slate-500">
                {{ item.new_ep?.title || item.season_title || '暂无更新信息' }}
              </p>
              <p class="text-[10px] text-slate-600">共 {{ item.total_count }} 集</p>

              <div class="mt-auto flex flex-col gap-1.5 pt-1.5">
                <template v-if="item.subscribed">
                  <span class="status-pill justify-center border-emerald-300/30 bg-emerald-400/10 text-emerald-200">
                    <CheckCircle2 :size="11" />
                    已追更
                  </span>
                  <div class="grid grid-cols-2 gap-1.5">
                    <button
                      type="button"
                      class="btn-ghost px-1.5 py-1.5 text-[11px]"
                      @click="focusSubscription(item.subscription_id)"
                    >
                      查看进度
                    </button>
                    <button
                      type="button"
                      class="btn-primary px-1.5 py-1.5 text-[11px]"
                      :disabled="busy !== null"
                      @click="openEpisodeDialog(item.season_id, item.title, true)"
                    >
                      选集下载
                    </button>
                  </div>
                </template>
                <template v-else>
                  <button
                    type="button"
                    class="btn-primary px-2 py-1.5 text-[11px]"
                    :disabled="busy !== null"
                    @click="openEpisodeDialog(item.season_id, item.title, false)"
                  >
                    选集下载
                  </button>
                  <div class="grid grid-cols-2 gap-1.5">
                    <button
                      type="button"
                      class="btn-ghost px-1.5 py-1.5 text-[11px]"
                      :disabled="busy !== null"
                      @click="subscribe(item, 'watch')"
                    >
                      {{ isBusy(`watch-${item.season_id}`) ? '处理中…' : '追更' }}
                    </button>
                    <button
                      type="button"
                      class="btn-ghost px-1.5 py-1.5 text-[11px]"
                      :disabled="busy !== null"
                      @click="subscribe(item, 'all')"
                    >
                      {{ isBusy(`all-${item.season_id}`) ? '加入中…' : '下载全集' }}
                    </button>
                  </div>
                </template>
              </div>
            </div>
          </article>
        </div>

        <div v-if="canLoadMore" class="flex justify-center">
          <button type="button" class="btn-ghost" :disabled="loadingFollow" @click="loadFollow()">
            <Clapperboard :size="15" />
            {{ loadingFollow ? '加载中…' : '加载更多' }}
          </button>
        </div>
      </section>
    </template>

    <BangumiEpisodeDialog
      v-if="episodeTarget"
      :season-id="episodeTarget.seasonId"
      :title="episodeTarget.title"
      :subscribed="episodeTarget.subscribed"
      :busy="busy !== null"
      @close="episodeTarget = null"
      @confirm="downloadSelected"
    />

    <ConfirmDialog
      v-if="confirmTarget"
      title="取消追更"
      :message="`将停止跟踪《${confirmTarget.title}》的更新，已下载的文件不会被删除。`"
      confirm-label="取消追更"
      :busy="busy !== null"
      @cancel="confirmTarget = null"
      @confirm="unsubscribe"
    />
  </div>
</template>
