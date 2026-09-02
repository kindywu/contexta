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
  timeout: 15_000, // 默认 15s；生成/重跑类接口单独覆盖为 5 分钟
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

// ---- 类型（与后端 admin API 契约一致；键名精确 snake_case） ----

export interface AdminUser {
  phone: string
  status: 'normal' | 'banned'
  banned_reason: string | null
  created_at: number
  quota_word_daily: number | null
  today_word_lookups: number
}

export interface UsageRow {
  phone: string | null
  endpoint: string
  calls: number
  prompt_tokens: number
  completion_tokens: number
}

/** 段落（编辑请求与详情响应共用）：order_index 1 起（响应侧派生） */
export interface ArticleParagraph {
  order_index: number
  english_text: string
  chinese_translation: string
}

/** 槽位视图的当前文章（白名单列；source_url 可空）。 */
export interface SlotArticle {
  id: number
  category: string
  title_en: string
  title_zh: string
  source_url: string | null
  paragraph_count: number
  path: string
  run_date: string
}

/** 当前文章的最新审核行。 */
export interface SlotReview {
  id: number
  status: string
  reject_reason: string | null
  reviewed_by: string | null
  reviewed_at: string | null
}

/** 同槽全部 review 行（含当前行）倒序（新 → 旧）；关联 article_id（契约不含 id）。 */
export interface ReviewHistoryItem {
  article_id: number
  status: string
  reject_reason: string | null
  reviewed_by: string | null
  reviewed_at: string | null
}

/** 槽位视图行：槽位 + 当前文章 + 当前审核行 + 同槽审核历史。 */
export interface SlotView {
  slot_id: number
  slot_index: number
  difficulty: string
  status: string
  attempts: number
  thread_id: string
  article: SlotArticle | null
  review: SlotReview | null
  history: ReviewHistoryItem[]
}

/** 文章详情：articles 全行 + 段落 + review 行 + 所属槽位（slot_id/slot_index）。 */
export interface ArticleDetail {
  id: number
  batch_id: number
  category: string
  title_en: string
  title_zh: string
  source_url: string | null
  paragraph_count: number
  path: string
  run_date: string
  paragraphs: ArticleParagraph[]
  review: SlotReview | null
  slot_id: number | null
  slot_index: number | null
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

  // ---- 槽位审核视图 ----

  /** 某日全部槽位（slot_index 升序）：当前文章 + 审核行 + 同槽审核历史。 */
  listSlots: (date: string) =>
    http.get<unknown, SlotView[]>('/articles', { params: { date } }),

  /** 文章详情：articles 全行 + 段落 + review + 所属槽位。 */
  getArticleDetail: (id: number) => http.get<unknown, ArticleDetail>(`/articles/${id}`),

  /** 审核期编辑（仅 pending_review；服务端整体替换标题 + 段落，按请求序重编序号）。 */
  updateArticle: (
    id: number,
    payload: { title: string; paragraphs: ArticleParagraph[] },
  ) => http.put<unknown, unknown>(`/articles/${id}`, payload),

  approveArticle: (id: number) =>
    http.post<unknown, unknown>(`/articles/${id}/approve`, {}),

  /** 拒绝触发补生成可达分钟级（LLM 预算），与服务端契约一致的 5 分钟超时。 */
  rejectArticle: (id: number, reason?: string) =>
    http.post<unknown, unknown>(
      `/articles/${id}/reject`,
      { reason },
      { timeout: 300_000 },
    ),

  /** 失败/被拒槽位重跑：同步等引擎生成（分钟级），5 分钟超时。 */
  retrySlot: (id: number) =>
    http.post<unknown, unknown>(`/slots/${id}/retry`, {}, { timeout: 300_000 }),

  /** 手动补生成可达分钟级（15 篇 × LLM 串行），axios timeout 放宽到 5 分钟。 */
  generateArticles: (date: string, opts?: AxiosRequestConfig) =>
    http.post<unknown, unknown>('/articles/generate', { date }, { timeout: 300_000, ...opts }),
}
