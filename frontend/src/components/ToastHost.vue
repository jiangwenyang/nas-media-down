<script setup lang="ts">
import { CircleCheckBig, CircleX, Info } from 'lucide-vue-next'
import { useToast } from '../composables/useToast'

const { toasts, dismiss } = useToast()

const toneStyles: Record<string, string> = {
  info: 'border-white/10 bg-slate-900/90 text-slate-200',
  success: 'border-emerald-300/25 bg-emerald-950/80 text-emerald-100',
  error: 'border-rose-300/25 bg-rose-950/80 text-rose-100',
}

const toneIcons = {
  info: Info,
  success: CircleCheckBig,
  error: CircleX,
}
</script>

<template>
  <div
    class="pointer-events-none fixed inset-x-0 bottom-4 z-[80] flex justify-center px-4 sm:justify-end sm:pr-6"
  >
    <TransitionGroup
      tag="div"
      class="flex w-full max-w-sm flex-col gap-2"
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="translate-y-[8px] opacity-0"
      leave-active-class="transition duration-150 ease-in"
      leave-to-class="opacity-0"
    >
      <button
        v-for="toast in toasts"
        :key="toast.id"
        type="button"
        class="pointer-events-auto flex items-start gap-2.5 rounded-xl border px-3.5 py-2.5 text-left text-sm shadow-2xl backdrop-blur-xl"
        :class="toneStyles[toast.tone]"
        @click="dismiss(toast.id)"
      >
        <component :is="toneIcons[toast.tone]" :size="17" class="mt-0.5 shrink-0" />
        <span class="leading-snug">{{ toast.message }}</span>
      </button>
    </TransitionGroup>
  </div>
</template>
