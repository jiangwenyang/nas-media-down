import { ref } from 'vue'
import { api } from '../api'

const authenticated = ref<boolean | null>(null)
let checked = false

/** 登录状态与登录/登出动作（模块级单例）。 */
export function useAuth() {
  async function check(): Promise<void> {
    if (checked) return
    checked = true
    try {
      authenticated.value = (await api.me()).authenticated
    } catch {
      authenticated.value = false
    }
  }

  async function login(password: string): Promise<void> {
    await api.login(password)
    authenticated.value = true
  }

  async function logout(): Promise<void> {
    try {
      await api.logout()
    } finally {
      authenticated.value = false
      checked = true
    }
  }

  return { authenticated, check, login, logout }
}
