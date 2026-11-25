import { ref } from 'vue'

export interface Toast {
  id: number
  message: string
  tone: 'info' | 'success' | 'error'
}

const toasts = ref<Toast[]>([])
let sequence = 0

/** 轻量 toast 通知（模块级单例）。 */
export function useToast() {
  function dismiss(id: number): void {
    toasts.value = toasts.value.filter((toast) => toast.id !== id)
  }

  function push(message: string, tone: Toast['tone'] = 'info'): void {
    const id = ++sequence
    toasts.value = [...toasts.value, { id, message, tone }]
    window.setTimeout(() => dismiss(id), 4200)
  }

  return { toasts, push, dismiss }
}
