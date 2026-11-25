<script setup lang="ts">
import { AlertTriangle } from 'lucide-vue-next'

defineProps<{
  title: string
  message: string
  confirmLabel?: string
  busy?: boolean
}>()

defineEmits<{
  confirm: []
  cancel: []
}>()
</script>

<template>
  <Teleport to="body">
    <div
      class="animate-overlay-in fixed inset-0 z-[70] flex items-center justify-center bg-slate-950/70 px-4 backdrop-blur-sm"
      @click.self="$emit('cancel')"
    >
      <div class="animate-float-in glass-card w-full max-w-sm p-6">
        <div class="flex items-start gap-3">
          <span
            class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10 text-rose-300"
          >
            <AlertTriangle :size="18" />
          </span>
          <div class="min-w-0">
            <h3 class="text-sm font-semibold text-white">{{ title }}</h3>
            <p class="mt-1 text-xs leading-relaxed text-slate-400">{{ message }}</p>
          </div>
        </div>
        <div class="mt-5 flex justify-end gap-2">
          <button type="button" class="btn-ghost" :disabled="busy" @click="$emit('cancel')">
            取消
          </button>
          <button
            type="button"
            class="inline-flex items-center justify-center rounded-xl bg-rose-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-400 focus-visible:ring-2 focus-visible:ring-rose-300/70 focus-visible:outline-none disabled:opacity-50"
            :disabled="busy"
            @click="$emit('confirm')"
          >
            {{ confirmLabel || '确认删除' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
