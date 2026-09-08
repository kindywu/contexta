<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { message, Modal } from 'ant-design-vue'
import dayjs, { type Dayjs } from 'dayjs'
import {
  api,
  type ArticleDetail,
  type ArticleListItem,
  type ArticleParagraph,
  type ErrorSlotRow,
} from '../api'

const loading = ref(false)
const rows = ref<ArticleListItem[]>([])

// 服务端分页/排序状态（a-table change 事件回写）
const pagination = reactive({
  current: 1,
  pageSize: 15,
  total: 0,
})
const sorter = reactive<{ field: string; order: 'ascend' | 'descend' | undefined }>({
  field: '',
  order: undefined,
})

// 时间段过滤：默认当天；切换即刷新
const range = ref<[Dayjs, Dayjs]>([dayjs(), dayjs()])

// 状态过滤：'' = 全部（pending_review / approved / rejected 含 rejected_final）
const statusFilter = ref<string>('')

// 摘要统计（时间段内全量，不受状态筛选影响）；error_slots = 生成失败槽位数（articles 视角不可见）
const stats = ref({ total: 0, pending_review: 0, approved: 0, rejected: 0, error_slots: 0 })

// 异常槽位（error/rejected，无文章行）——摘要 tag 入口 + 重跑
const errorState = reactive({
  open: false,
  loading: false,
  runningId: 0,
  progress: '',
  items: [] as ErrorSlotRow[],
})

async function loadErrorSlots() {
  errorState.loading = true
  try {
    const [s, e] = [range.value[0].format('YYYY-MM-DD'), range.value[1].format('YYYY-MM-DD')]
    const res = await api.errorSlots(s, e)
    errorState.items = res.items ?? []
  } catch {
    // 拦截器已提示
  } finally {
    errorState.loading = false
  }
}

function openErrorSlots() {
  errorState.open = true
  loadErrorSlots()
}

const STAGE_TEXT: Record<string, string> = {
  start: '开始重跑…',
  generating: '生成中（分钟级，请稍候）…',
  success: '生成成功',
  error: '生成失败',
}

/** 槽位重跑（SSE 进度流，服务端完成/失败后关流；成功即刷新列表 + 异常列表）。 */
async function retryErrorSlot(id: number) {
  errorState.runningId = id
  errorState.progress = '连接到服务端…'
  try {
    await api.retrySlot(id, (p) => {
      errorState.progress = p.detail ?? STAGE_TEXT[p.stage] ?? ''
    })
    message.success('槽位重跑完成')
    await Promise.all([load(), loadErrorSlots()])
  } catch (e) {
    message.error(e instanceof Error ? e.message : '重跑失败')
  } finally {
    errorState.runningId = 0
    errorState.progress = ''
  }
}

// 补生成：独立日期输入（防误触，不默认今天）
const generateState = reactive({
  date: undefined as Dayjs | undefined,
  running: false,
})

// 详情抽屉（查看/编辑入口；数据来自列表行 + getArticleDetail）
const drawer = reactive({
  open: false,
  row: null as ArticleListItem | null,
  detail: null as ArticleDetail | null,
  loading: false,
})

// 抽屉内编辑 Modal（仅 pending_review 且当前指向；标题 + 段落整体替换）
const editing = reactive({
  active: false,
  saving: false,
  title: '',
  paragraphs: [] as ArticleParagraph[],
})

// 拒绝弹窗
const rejectState = reactive({
  open: false,
  row: null as ArticleListItem | null,
  reason: '',
  submitting: false,
})

const REVIEW_STATUS: Record<string, { text: string; color: string }> = {
  pending_review: { text: '待审核', color: 'warning' },
  approved: { text: '已通过', color: 'green' },
  rejected: { text: '已拒绝', color: 'red' },
  rejected_final: { text: '已拒绝（终）', color: 'default' },
}

const DIFFICULTY_COLOR: Record<string, string> = {
  LOW: 'green',
  MEDIUM: 'orange',
  HIGH: 'red',
}

const STATUS_OPTIONS = [
  { value: '', label: '全部' },
  { value: 'pending_review', label: '待审核' },
  { value: 'approved', label: '已通过' },
  { value: 'rejected', label: '已拒绝' },
]

function reviewStatusMeta(status: string) {
  return REVIEW_STATUS[status] ?? { text: status, color: 'default' }
}

function fmtDate(d: Dayjs | undefined): string {
  return d ? d.format('YYYY-MM-DD') : ''
}

/** 服务端 datetime('now') 为 UTC（YYYY-MM-DD HH:MM:SS），转本地时间显示。 */
function fmtUtcTime(s: string | null | undefined): string {
  return s ? dayjs(new Date(s.replace(' ', 'T') + 'Z')).format('YYYY-MM-DD HH:mm') : '—'
}

/** 抽屉标题：详情标题 > 列表行标题 > 兜底。 */
const drawerTitle = computed(
  () => drawer.detail?.title_en || drawer.row?.title_en || '文章详情',
)

function slotLabel(row: { slot_index: number | null }): string {
  return row.slot_index == null ? '—' : `#${row.slot_index + 1}` // 存储 0 基，展示 1 基
}

/** 重跑条件：文章被拒（非终）且仍为槽位当前指向（补生成未成/失败场景）。 */
function canRetry(row: ArticleListItem): boolean {
  return row.review?.status === 'rejected' && row.is_current
}

/** 可审核提交：待审且文章是槽位现指向（旧文不可再审，守卫在服务端）。row 可空以兼容抽屉里 drawer.row 未就绪态。 */
function canReview(row: ArticleListItem | null): boolean {
  return !!row && row.review?.status === 'pending_review' && row.is_current
}

// ---- 数据加载 ----

// 请求序号守卫：切换筛选后旧请求晚返回时丢弃，避免覆盖新列表 / 错序复位 loading
let loadSeq = 0

async function load() {
  const [start, end] = range.value
  const seq = ++loadSeq
  loading.value = true
  try {
    const result = await api.listArticles({
      start_date: fmtDate(start),
      end_date: fmtDate(end),
      status: statusFilter.value || undefined,
      page: pagination.current,
      page_size: pagination.pageSize,
      sort_by: sorter.field || undefined,
      sort_dir: sorter.order === 'ascend' ? 'asc' : sorter.order === 'descend' ? 'desc' : undefined,
    })
    if (seq === loadSeq) {
      rows.value = result.items
      pagination.total = result.total
      stats.value = result.stats
      loading.value = false
    }
  } catch {
    // 拦截器已提示
    if (seq === loadSeq) loading.value = false
  }
}

onMounted(load)

function onFilterChange() {
  pagination.current = 1
  load()
}

/** 统计项点击 → 设置状态筛选（再次点击取消）。 */
function pickStatus(s: string) {
  statusFilter.value = statusFilter.value === s ? '' : s
  onFilterChange()
}

/** a-table change：分页/排序变化 → 回写状态并重载（服务端分页+排序）。 */
function onTableChange(
  p: { current: number; pageSize: number },
  _filters: unknown,
  s: { field: string; order: 'ascend' | 'descend' | undefined },
) {
  let changed = false
  if (p.pageSize !== pagination.pageSize) {
    changed = true
    pagination.pageSize = p.pageSize
    pagination.current = 1 // 页大小变化回第一页
  } else if (p.current !== pagination.current) {
    changed = true
    pagination.current = p.current
  }
  const nextField = s?.field ?? ''
  const nextOrder = s?.order
  if (nextField !== sorter.field || nextOrder !== sorter.order) {
    changed = true
    sorter.field = nextField
    sorter.order = nextOrder
    pagination.current = 1 // 排序变化回第一页
  }
  if (changed) load()
}

// 补生成：确认后刷新当前列表（若补的不是当前日期，提示用户切换查看）
async function generate() {
  const d = fmtDate(generateState.date)
  if (!d) {
    message.warning('请先选择补生成日期')
    return
  }
  generateState.running = true
  try {
    await api.generateArticles(d)
    message.success(`已提交 ${d} 的文章生成`)
    await load()
  } catch {
    // 拦截器已提示（含 5 分钟超时）
  } finally {
    generateState.running = false
  }
}

// ---- 详情抽屉 ----

// 详情请求序号守卫：关 A 开 B 时 A 的详情晚到不覆盖 B
let drawerSeq = 0

async function openDrawer(row: ArticleListItem) {
  const seq = ++drawerSeq
  drawer.row = row
  drawer.detail = null
  drawer.open = true
  drawer.loading = true
  try {
    const result = await api.getArticleDetail(row.id)
    if (seq === drawerSeq) {
      drawer.detail = result
      drawer.loading = false
    }
  } catch {
    // 拦截器已提示（如 404：文章已不存在）
    if (seq === drawerSeq) drawer.loading = false
  }
}

// ---- 审核操作（approve / reject / retry） ----

function confirmApprove(row: ArticleListItem) {
  Modal.confirm({
    title: '通过文章',
    content: `确认通过《${row.title_en}》？通过后不可再次修改。`,
    okText: '确认通过',
    cancelText: '取消',
    onOk: async () => {
      try {
        await api.approveArticle(row.id)
        message.success(`已通过《${row.title_en}》`)
        drawer.open = false
        await load()
      } catch {
        // 拦截器已提示（如 404：文章已不在待审状态/已被并发审核）
      }
    },
  })
}

function openReject(row: ArticleListItem) {
  rejectState.row = row
  rejectState.reason = ''
  rejectState.open = true
}

async function submitReject() {
  const row = rejectState.row
  if (!row) return
  rejectState.submitting = true
  try {
    await api.rejectArticle(row.id, rejectState.reason)
    message.success('已拒绝，将自动补生成')
    rejectState.open = false
    drawer.open = false
    await load()
  } catch {
    // 拦截器已提示
  } finally {
    rejectState.submitting = false
  }
}

function confirmRetry(row: ArticleListItem) {
  if (row.slot_id == null) return
  Modal.confirm({
    title: '重跑槽位',
    content: `确认重跑槽位 ${slotLabel(row)}？将重新生成该槽位文章（可替换当前被拒内容）。`,
    okText: '确认重跑',
    cancelText: '取消',
    onOk: async () => {
      try {
        await api.retrySlot(row.slot_id!)
        message.success(`槽位 ${slotLabel(row)} 重跑完成`)
        await load()
      } catch {
        // 拦截器已提示（含 5 分钟超时）
      }
    },
  })
}

// ---- 抽屉内编辑（仅 pending_review 且当前指向） ----

function startEdit() {
  const detail = drawer.detail
  if (!detail) return
  editing.title = detail.title_en || ''
  editing.paragraphs = detail.paragraphs.map((p) => ({ ...p }))
  editing.active = true
}

function cancelEdit() {
  editing.active = false
  editing.title = ''
  editing.paragraphs = []
}

function addParagraph() {
  editing.paragraphs.push({
    order_index: editing.paragraphs.length + 1,
    english_text: '',
    chinese_translation: '',
  })
}

function removeParagraph(index: number) {
  editing.paragraphs.splice(index, 1)
  // 重新编号（服务端按请求序重编，这里保持展示连续）
  editing.paragraphs.forEach((p, i) => {
    p.order_index = i + 1
  })
}

async function saveEdit() {
  const row = drawer.row
  if (!row) return
  const title = editing.title.trim()
  if (!title) {
    message.warning('标题不能为空')
    return
  }
  if (editing.paragraphs.length === 0) {
    message.warning('至少保留一个段落')
    return
  }
  if (
    editing.paragraphs.some(
      (p) => !p.english_text.trim() && !p.chinese_translation.trim(),
    )
  ) {
    message.warning('每段英文与中文至少填写一项')
    return
  }
  editing.saving = true
  try {
    await api.updateArticle(row.id, {
      title,
      paragraphs: editing.paragraphs.map((p) => ({
        order_index: p.order_index,
        english_text: p.english_text,
        chinese_translation: p.chinese_translation,
      })),
    })
    message.success(`已保存《${title}》`)
    editing.active = false
    drawer.open = false
    await load()
  } catch {
    // 拦截器已提示（如 404：文章已过审/已被替换）
  } finally {
    editing.saving = false
  }
}
</script>

<template>
  <div class="articles-page">
    <a-card class="filter-card">
      <div class="filter-row">
        <span class="filter-label">时间：</span>
        <a-range-picker
          v-model:value="range"
          :allow-clear="false"
          format="YYYY-MM-DD"
          style="width: 260px"
          @change="onFilterChange"
        />
        <span class="filter-label">状态：</span>
        <a-select
          v-model:value="statusFilter"
          :options="STATUS_OPTIONS"
          style="width: 130px"
          @change="onFilterChange"
        />
        <span class="spacer" />
        <span class="generate-label">补生成：</span>
        <a-date-picker v-model:value="generateState.date" placeholder="选择日期" />
        <a-button
          type="primary"
          :loading="generateState.running"
          :disabled="!generateState.date"
          @click="generate"
        >
          补生成
        </a-button>
      </div>

      <!-- 摘要统计：时间段内全量（不受状态筛选影响），点击可筛选 -->
      <div class="stats-row">
        <a-tag
          v-for="s in [
            { key: '', label: '总计', value: stats.total, color: 'blue' },
            { key: 'pending_review', label: '待审核', value: stats.pending_review, color: 'orange' },
            { key: 'approved', label: '已通过', value: stats.approved, color: 'green' },
            { key: 'rejected', label: '已拒绝', value: stats.rejected, color: 'red' },
          ]"
          :key="s.key"
          :class="{ 'stats-tag-active': statusFilter === s.key }"
          :color="statusFilter === s.key ? s.color : undefined"
          class="stats-tag"
          @click="pickStatus(s.key)"
        >
          {{ s.label }} {{ s.value }}
        </a-tag>
        <a-tag
          v-if="stats.error_slots > 0"
          color="magenta"
          class="stats-tag"
          @click="openErrorSlots()"
        >
          异常槽位 {{ stats.error_slots }}
        </a-tag>
      </div>
    </a-card>

    <!-- 异常槽位抽屉：error/rejected 槽一句话简报 + 单槽重跑 -->
    <a-modal v-model:open="errorState.open" title="异常槽位" :width="760" :footer="null">
      <a-table
        :data-source="errorState.items"
        :loading="errorState.loading"
        :pagination="false"
        row-key="id"
        size="small"
      >
        <a-table-column title="槽位" data-index="slot_index" width="110">
          <template #default="{ record }">
            <span style="font-weight: 600">slot {{ record.slot_index }}</span>
            <a-tag size="small">{{ record.difficulty }}</a-tag>
          </template>
        </a-table-column>
        <a-table-column title="状态" data-index="status" width="100" />
        <a-table-column title="更新时间" data-index="updated_at" width="180" />
        <a-table-column title="操作" key="action" width="90">
          <template #default="{ record }">
            <a-button
              type="link"
              size="small"
              :loading="errorState.runningId === record.id"
              :disabled="errorState.runningId !== 0"
              @click="retryErrorSlot(record.id)"
            >
              重跑
            </a-button>
          </template>
        </a-table-column>
      </a-table>
      <div v-if="errorState.progress" style="margin-top: 10px; color: #666">
        {{ errorState.progress }}
      </div>
    </a-modal>

    <a-card :loading="loading" class="list-card">
      <a-table
        :data-source="rows"
        :pagination="{
          current: pagination.current,
          pageSize: pagination.pageSize,
          total: pagination.total,
          showSizeChanger: true,
          pageSizeOptions: ['15', '30', '45'],
          showTotal: (t: number) => `共 ${t} 篇`,
        }"
        row-key="id"
        size="middle"
        @change="onTableChange"
      >
        <a-table-column title="日期" data-index="run_date" sorter width="110">
          <template #default="{ record }">{{ record.run_date }}</template>
        </a-table-column>
        <a-table-column title="槽位" data-index="slot_index" sorter width="120">
          <template #default="{ record }">
            <span style="font-weight: 600">{{ slotLabel(record) }}</span>
            <a-tag v-if="record.slot_index != null && !record.is_current" color="default" size="small">
              已替换
            </a-tag>
          </template>
        </a-table-column>
        <a-table-column title="难度" data-index="difficulty" sorter width="90">
          <template #default="{ record }">
            <a-tag :color="DIFFICULTY_COLOR[record.difficulty] || 'default'">
              {{ record.difficulty }}
            </a-tag>
          </template>
        </a-table-column>
        <a-table-column title="分类" data-index="category" sorter width="150">
          <template #default="{ record }">{{ record.category }}</template>
        </a-table-column>
        <a-table-column title="标题" data-index="title_en" width="220">
          <template #default="{ record }">
            <span class="title-cell">{{ record.title_en }}</span>
          </template>
        </a-table-column>
        <a-table-column title="状态" data-index="status" sorter width="120">
          <template #default="{ record }">
            <a-tag v-if="record.review" :color="reviewStatusMeta(record.review.status).color">
              {{ reviewStatusMeta(record.review.status).text }}
            </a-tag>
            <span v-else class="placeholder-text">无审核记录</span>
          </template>
        </a-table-column>
        <a-table-column title="生成时间" data-index="created_at" sorter width="140">
          <template #default="{ record }">{{ fmtUtcTime(record.created_at) }}</template>
        </a-table-column>
        <a-table-column title="操作" width="200">
          <template #default="{ record }">
            <a-button type="link" size="small" @click="openDrawer(record)">查看</a-button>
            <template v-if="canReview(record)">
              <a-button type="link" size="small" @click="confirmApprove(record)">通过</a-button>
              <a-button type="link" danger size="small" @click="openReject(record)">拒绝</a-button>
              <a-button type="link" size="small" @click="startEdit">编辑</a-button>
            </template>
            <a-button v-if="canRetry(record)" type="link" size="small" @click="confirmRetry(record)">
              重跑
            </a-button>
          </template>
        </a-table-column>
      </a-table>
    </a-card>

    <!-- 详情抽屉：标题 + 段落 + 来源 + 审核信息 + 槽位历史时间线 -->
    <a-drawer v-model:open="drawer.open" :width="720" :title="drawerTitle">
      <a-spin :spinning="drawer.loading">
        <template v-if="drawer.detail">
          <div class="detail-title">
            <div class="title-en">{{ drawer.detail.title_en }}</div>
            <div v-if="drawer.detail.title_zh" class="title-zh">{{ drawer.detail.title_zh }}</div>
          </div>

          <a-descriptions :column="2" size="small" bordered class="drawer-meta">
            <a-descriptions-item label="槽位">
              {{ slotLabel(drawer.detail) }}
            </a-descriptions-item>
            <a-descriptions-item label="难度">
              <a-tag :color="DIFFICULTY_COLOR[drawer.detail.difficulty] || 'default'">
                {{ drawer.detail.difficulty }}
              </a-tag>
            </a-descriptions-item>
            <a-descriptions-item label="日期">{{ drawer.detail.run_date }}</a-descriptions-item>
            <a-descriptions-item label="段落数">{{ drawer.detail.paragraph_count }}</a-descriptions-item>
            <a-descriptions-item label="分类" :span="2">{{ drawer.detail.category }}</a-descriptions-item>
            <a-descriptions-item label="归属">
              <span v-if="drawer.detail.slot_index != null && !drawer.row?.is_current" class="old-article-tag">
                已替换（旧文，不可再审核）
              </span>
              <span v-else>当前槽位指向</span>
            </a-descriptions-item>
            <a-descriptions-item label="来源" :span="2">
              <a
                v-if="drawer.detail.source_url"
                :href="drawer.detail.source_url"
                target="_blank"
                rel="noreferrer"
              >
                {{ drawer.detail.source_url }}
              </a>
              <span v-else class="placeholder-text">—</span>
            </a-descriptions-item>
          </a-descriptions>

          <!-- 审核信息 -->
          <div v-if="drawer.detail.review" class="review-block">
            <div class="block-title">审核信息</div>
            <a-descriptions :column="2" size="small" bordered>
              <a-descriptions-item label="状态">
                <a-tag :color="reviewStatusMeta(drawer.detail.review.status).color">
                  {{ reviewStatusMeta(drawer.detail.review.status).text }}
                </a-tag>
              </a-descriptions-item>
              <a-descriptions-item label="审核人">
                {{ drawer.detail.review.reviewed_by || '—' }}
              </a-descriptions-item>
              <a-descriptions-item label="审核时间" :span="2">
                {{ fmtUtcTime(drawer.detail.review.reviewed_at) }}
              </a-descriptions-item>
              <a-descriptions-item v-if="drawer.detail.review.reject_reason" label="拒绝原因" :span="2">
                {{ drawer.detail.review.reject_reason }}
              </a-descriptions-item>
            </a-descriptions>
          </div>

          <!-- 段落双语 -->
          <div class="block-title">正文段落</div>
          <div class="paragraph-list">
            <div
              v-for="p in drawer.detail.paragraphs"
              :key="p.order_index"
              class="paragraph-item"
            >
              <div class="para-en">
                <span class="para-no">{{ p.order_index }}.</span>
                {{ p.english_text }}
              </div>
              <div v-if="p.chinese_translation" class="para-zh">{{ p.chinese_translation }}</div>
            </div>
          </div>

          <!-- 槽位审核历史时间线 -->
          <div class="block-title">槽位历史（同槽全部审核记录）</div>
          <a-timeline v-if="drawer.detail.history.length" class="history-timeline">
            <a-timeline-item v-for="(h, i) in drawer.detail.history" :key="i">
              <div class="history-row">
                <a-tag :color="reviewStatusMeta(h.status).color">
                  {{ reviewStatusMeta(h.status).text }}
                </a-tag>
                <span class="history-article">文章 #{{ h.article_id }}</span>
                <span v-if="h.reviewed_by" class="history-meta">审核人：{{ h.reviewed_by }}</span>
                <span v-if="h.reviewed_at" class="history-meta">时间：{{ fmtUtcTime(h.reviewed_at) }}</span>
              </div>
              <div v-if="h.reject_reason" class="history-reason">原因：{{ h.reject_reason }}</div>
            </a-timeline-item>
          </a-timeline>
          <div v-else class="placeholder-text">暂无审核记录</div>

          <!-- pending_review：抽屉内审核/编辑操作 -->
          <div
            v-if="canReview(drawer.row!) && !editing.active"
            class="drawer-actions"
          >
            <a-button type="primary" @click="confirmApprove(drawer.row!)">通过</a-button>
            <a-button danger @click="openReject(drawer.row!)">拒绝</a-button>
            <a-button @click="startEdit">编辑</a-button>
          </div>
        </template>
        <div v-else-if="!drawer.loading" class="no-content">
          该文章不存在或已被移除。
        </div>
      </a-spin>
    </a-drawer>

    <!-- 编辑 Modal：标题 + 段落（en/zh 双文本域，可增删） -->
    <a-modal
      v-model:open="editing.active"
      title="编辑文章（仅审核期）"
      :width="720"
      :confirm-loading="editing.saving"
      ok-text="保存"
      cancel-text="取消"
      @ok="saveEdit"
      @cancel="cancelEdit"
    >
      <div class="edit-title-row">
        <span class="edit-label">标题</span>
        <a-input
          v-model:value="editing.title"
          placeholder="文章标题（英文）"
          maxlength="200"
          show-count
        />
      </div>
      <div
        v-for="(p, idx) in editing.paragraphs"
        :key="idx"
        class="paragraph-item edit-paragraph"
      >
        <div class="edit-para-head">
          <span class="para-no">{{ idx + 1 }}.</span>
          <a-button type="link" danger size="small" @click="removeParagraph(idx)">
            删除
          </a-button>
        </div>
        <a-textarea
          v-model:value="p.english_text"
          :rows="2"
          placeholder="英文"
          maxlength="2000"
          show-count
        />
        <a-textarea
          v-model:value="p.chinese_translation"
          :rows="2"
          placeholder="中文"
          maxlength="2000"
          show-count
          class="edit-zh"
        />
      </div>
      <a-button type="dashed" block @click="addParagraph">+ 添加段落</a-button>
    </a-modal>

    <!-- 拒绝弹窗 -->
    <a-modal
      v-model:open="rejectState.open"
      title="拒绝文章"
      :confirm-loading="rejectState.submitting"
      ok-text="确认拒绝"
      cancel-text="取消"
      @ok="submitReject"
    >
      <p>拒绝后该篇标记为「已拒绝」，并自动触发补生成（达上限则终拒）。</p>
      <a-textarea
        v-model:value="rejectState.reason"
        placeholder="拒绝原因（可选）"
        :rows="3"
        maxlength="200"
        show-count
      />
    </a-modal>
  </div>
</template>

<style scoped>
.filter-card {
  margin-bottom: 16px;
}
.filter-row {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.filter-label {
  color: #666;
}
.spacer {
  flex: 1;
}
.generate-label {
  color: #666;
}
.stats-row {
  margin-top: 12px;
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.stats-tag {
  cursor: pointer;
  font-size: 14px;
  padding: 4px 10px;
}
.stats-tag-active {
  font-weight: 600;
  border-width: 2px;
}
.placeholder-text {
  color: #999;
  font-style: italic;
}
.title-cell {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.old-article-tag {
  color: #c00;
}
.drawer-meta {
  margin-bottom: 16px;
}
.detail-title {
  margin-bottom: 16px;
}
.title-en {
  font-size: 18px;
  font-weight: 600;
  line-height: 1.4;
}
.title-zh {
  margin-top: 4px;
  color: #666;
}
.review-block {
  margin-bottom: 16px;
}
.block-title {
  font-size: 14px;
  font-weight: 600;
  color: #333;
  margin: 16px 0 8px;
}
.paragraph-list {
  max-height: 40vh;
  overflow-y: auto;
}
.paragraph-item {
  margin-bottom: 16px;
  padding: 12px;
  border: 1px solid #f0f0f0;
  border-radius: 6px;
}
.para-en {
  font-size: 15px;
  line-height: 1.6;
}
.para-no {
  color: #999;
  margin-right: 6px;
}
.para-zh {
  margin-top: 6px;
  color: #666;
  line-height: 1.6;
}
.history-timeline {
  margin-top: 8px;
}
.history-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.history-article {
  font-weight: 500;
}
.history-meta {
  color: #999;
  font-size: 12px;
}
.history-reason {
  margin-top: 4px;
  color: #c00;
  font-size: 13px;
}
.edit-title-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 16px;
}
.edit-label {
  color: #666;
  flex-shrink: 0;
}
.edit-paragraph {
  border-color: #d9d9d9;
}
.edit-para-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}
.edit-zh {
  margin-top: 8px;
}
.no-content {
  color: #999;
  padding: 24px 0;
  text-align: center;
}
.drawer-actions {
  margin-top: 24px;
  display: flex;
  gap: 12px;
}
</style>
