// API 客户端：统一 envelope 解包 + token 注入 + 401 跳登录。
// 服务端契约：成功 {code:0, data}；失败非 2xx + {code, message, error_code}。
import axios, { type AxiosRequestConfig } from 'axios'
import { message } from 'ant-design-vue'

const TOKEN_KEY = 'ctx_admin_token'

export function getToken(): string {
  return localStorage.getItem(TOKEN_KEY) || ''
}

export function setToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token)
}

export function clearToken() {
  localStorage.removeItem(TOKEN_KEY)
}

export function redirectLogin() {
  clearToken()
  // 走完整跳转，让路由守卫接管（避免直接 location 丢 SPA 状态）
  if (location.pathname !== '/admin/login') {
    location.href = '/admin/login'
  }
}

const http = axios.create({
  baseURL: '/api/admin',
  timeout: 15_000, // 默认 15s；生成接口单独覆盖为 5 分钟
})

http.interceptors.request.use((config) => {
  const token = getToken()
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

http.interceptors.response.use(
  (resp) => {
    const body = resp.data
    // 契约：HTTP 200 + code:0 视为成功，data 直接透出
    if (body && typeof body === 'object' && 'code' in body) {
      if (body.code === 0) return body.data
      message.error(body.message || '请求失败')
      return Promise.reject(new Error(body.message || '请求失败'))
    }
    return body
  },
  (err) => {
    const status: number | undefined = err.response?.status
    const data = err.response?.data
    if (status === 401) {
      message.error('登录已过期，请重新登录')
      redirectLogin()
    } else if (data?.message) {
      message.error(data.message)
    } else if (err.code === 'ECONNABORTED') {
      message.error('请求超时，请稍后重试')
    } else {
      message.error(`请求失败（${status ?? '网络错误'}）`)
    }
    return Promise.reject(err)
  },
)

// ---- 类型（与后端 admin API 契约一致） ----

export interface AdminUser {
  phone: string
  status: 'normal' | 'banned'
  banned_reason: string | null
  created_at: number
  quota_word_daily: number | null
  today_word_lookups: number
}

export interface ArticleItem {
  id: number
  title: string | null
  target_date: string
  difficulty: string
  content_category: string
  order_index: number
  status: string
  regenerate_count: number
}

export interface ArticleParagraph {
  order_index: number
  english_text: string
  chinese_translation: string
}

export interface ArticleDetail extends ArticleItem {
  paragraphs: ArticleParagraph[]
}

export interface UsageRow {
  phone: string | null
  endpoint: string
  calls: number
  prompt_tokens: number
  completion_tokens: number
}

export interface PromptItem {
  key: string
  content: string
  // Unix millis；0 = 种子默认值（从未修改）
  updated_at: number
}

// ---- 接口函数 ----

export const api = {
  login: (username: string, password: string) =>
    http.post<unknown, { token: string }>('/login', { username, password }),

  listUsers: () => http.get<unknown, AdminUser[]>('/users'),

  banUser: (phone: string, reason: string) =>
    http.post<unknown, unknown>(`/users/${encodeURIComponent(phone)}/ban`, { reason }),

  unbanUser: (phone: string) =>
    http.post<unknown, unknown>(`/users/${encodeURIComponent(phone)}/unban`, {}),

  setQuota: (phone: string, wordDaily: number | null) =>
    http.put<unknown, unknown>(`/users/${encodeURIComponent(phone)}/quota`, {
      word_daily: wordDaily,
    }),

  usage: () => http.get<unknown, UsageRow[]>('/usage'),

  listPrompts: () => http.get<unknown, PromptItem[]>('/prompts'),

  updatePrompt: (key: string, content: string) =>
    http.put<unknown, unknown>(`/prompts/${encodeURIComponent(key)}`, { content }),

  listArticles: (status?: string, date?: string) => {
    const params: Record<string, string> = {}
    if (status) params.status = status
    if (date) params.date = date
    return http.get<unknown, ArticleItem[]>('/articles', { params })
  },

  articleDetail: (id: number) => http.get<unknown, ArticleDetail>(`/articles/${id}`),

  // 审核期编辑（仅 pending_review；服务端整体替换标题 + 段落）
  updateArticle: (id: number, title: string, paragraphs: ArticleParagraph[]) =>
    http.put<unknown, unknown>(`/articles/${id}`, { title, paragraphs }),

  approveArticle: (id: number) =>
    http.post<unknown, unknown>(`/articles/${id}/approve`, {}),

  rejectArticle: (id: number, reason: string) =>
    http.post<unknown, unknown>(
      `/articles/${id}/reject`,
      { reason },
      { timeout: 300_000 }, // 拒绝触发补生成可达 90s+（LLM 预算），与服务端契约一致的 5 分钟超时
    ),

  // 手动生成可达分钟级（15 篇 × LLM 串行），axios timeout 放宽到 5 分钟
  generateArticles: (date: string, opts?: AxiosRequestConfig) =>
    http.post<unknown, unknown>('/articles/generate', { date }, { timeout: 300_000, ...opts }),
}
