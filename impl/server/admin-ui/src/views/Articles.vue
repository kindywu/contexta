<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { message, Modal } from 'ant-design-vue'
import dayjs, { type Dayjs } from 'dayjs'
import { api, type ArticleDetail, type ArticleParagraph, type SlotView } from '../api'

const loading = ref(false)
const slots = ref<SlotView[]>([])

// 日期选择：默认今天，切换即刷新
const date = ref<Dayjs>(dayjs())

// 补生成：独立日期输入（防误触，不默认今天）
const generateState = reactive({
  date: undefined as Dayjs | undefined,
  running: false,
})

// 详情抽屉（查看/编辑入口；数据来自 listSlots 行 + getArticleDetail）
const drawer = reactive({
  open: false,
  slot: null as SlotView | null,
  detail: null as ArticleDetail | null,
  loading: false,
})

// 抽屉内编辑 Modal（仅 pending_review；标题 + 段落整体替换）
const editing = reactive({
  active: false,
  saving: false,
  title: '',
  paragraphs: [] as ArticleParagraph[],
})

// 拒绝弹窗
const rejectState = reactive({
  open: false,
  slot: null as SlotView | null,
  reason: '',
  submitting: false,
})

// ---- 状态展示 ----

const SLOT_STATUS: Record<string, { text: string; color: string }> = {
  success: { text: '成功', color: 'blue' },
  pending: { text: '生成中', color: 'processing' },
  error: { text: '生成失败', color: '#595959' },
  rejected: { text: '生成拒绝', color: '#595959' },
}

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

function slotStatusMeta(status: string) {
  return SLOT_STATUS[status] ?? { text: status, color: 'default' }
}

function reviewStatusMeta(status: string) {
  return REVIEW_STATUS[status] ?? { text: status, color: 'default' }
}

function fmtDate(d: Dayjs | undefined): string {
  return d ? d.format('YYYY-MM-DD') : ''
}

/** 抽屉标题：详情标题 > 槽位当前文章标题 > 兜底。 */
const drawerTitle = computed(
  () => drawer.detail?.title_en || drawer.slot?.article?.title_en || '槽位详情',
)

function slotLabel(slot: SlotView): number {
  return slot.slot_index + 1 // 存储 0 基，展示 1 基
}

/** 无文章（error/rejected）占位文案；pending = 生成中。 */
function emptyText(slot: SlotView): string {
  return slot.status === 'pending' ? '生成中…' : '无文章'
}

/** 重跑条件：槽位终态且无当前文章（初始生成失败/被拒），或当前文章已被拒绝且补生成未成（review 仍为现指向）。 */
function canRetry(slot: SlotView): boolean {
  if (!slot.review && (slot.status === 'error' || slot.status === 'rejected')) return true
  return slot.review?.status === 'rejected'
}

// ---- 数据加载 ----

async function load() {
  const d = fmtDate(date.value)
  if (!d) return
  loading.value = true
  try {
    slots.value = await api.listSlots(d)
  } catch {
    // 拦截器已提示
  } finally {
    loading.value = false
  }
}

onMounted(load)

function onDateChange() {
  load()
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
    if (d === fmtDate(date.value)) {
      await load()
    } else {
      message.info(`可在顶部切换到 ${d} 查看结果`)
    }
  } catch {
    // 拦截器已提示（含 5 分钟超时）
  } finally {
    generateState.running = false
  }
}

// ---- 详情抽屉 ----

async function openDrawer(slot: SlotView) {
  if (!slot.article) return
  drawer.slot = slot
  drawer.detail = null
  drawer.open = true
  drawer.loading = true
  try {
    drawer.detail = await api.getArticleDetail(slot.article.id)
  } catch {
    // 拦截器已提示（如 404：文章已不存在）
  } finally {
    drawer.loading = false
  }
}

// ---- 审核操作（approve / reject / retry） ----

function confirmApprove(slot: SlotView) {
  const article = slot.article
  if (!article) return
  Modal.confirm({
    title: '通过文章',
    content: `确认通过《${article.title_en}》？通过后不可再次修改。`,
    okText: '确认通过',
    cancelText: '取消',
    onOk: async () => {
      try {
        await api.approveArticle(article.id)
        message.success(`已通过《${article.title_en}》`)
        drawer.open = false
        await load()
      } catch {
        // 拦截器已提示（如 404：文章已不在待审状态/已被并发审核）
      }
    },
  })
}

function openReject(slot: SlotView) {
  rejectState.slot = slot
  rejectState.reason = ''
  rejectState.open = true
}

async function submitReject() {
  const slot = rejectState.slot
  const article = slot?.article
  if (!slot || !article) return
  rejectState.submitting = true
  try {
    await api.rejectArticle(article.id, rejectState.reason)
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

function confirmRetry(slot: SlotView) {
  Modal.confirm({
    title: '重跑槽位',
    content: `确认重跑槽位 #${slotLabel(slot)}？将重新生成该槽位文章（可替换当前被拒/失败内容）。`,
    okText: '确认重跑',
    cancelText: '取消',
    onOk: async () => {
      try {
        await api.retrySlot(slot.slot_id)
        message.success(`槽位 #${slotLabel(slot)} 重跑完成`)
        await load()
      } catch {
        // 拦截器已提示（含 5 分钟超时）
      }
    },
  })
}

// ---- 抽屉内编辑（仅 pending_review） ----

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
  const slot = drawer.slot
  const article = slot?.article
  if (!slot || !article) return
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
    await api.updateArticle(article.id, {
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
        <span class="filter-label">日期：</span>
        <a-date-picker
          v-model:value="date"
          placeholder="选择日期"
          style="width: 180px"
          @change="onDateChange"
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
    </a-card>

    <a-card :loading="loading" class="list-card">
      <a-table :data-source="slots" :pagination="false" row-key="slot_id" size="middle">
        <a-table-column title="槽位" width="80">
          <template #default="{ record }">
            <span style="font-weight: 600">#{{ slotLabel(record) }}</span>
          </template>
        </a-table-column>
        <a-table-column title="难度" width="90">
          <template #default="{ record }">
            <a-tag :color="DIFFICULTY_COLOR[record.difficulty] || 'default'">
              {{ record.difficulty }}
            </a-tag>
          </template>
        </a-table-column>
        <a-table-column title="分类" width="160">
          <template #default="{ record }">
            <span v-if="record.article">{{ record.article.category }}</span>
            <span v-else class="placeholder-text">{{ emptyText(record) }}</span>
          </template>
        </a-table-column>
        <a-table-column title="状态" width="200">
          <template #default="{ record }">
            <a-tag :color="slotStatusMeta(record.status).color">
              {{ slotStatusMeta(record.status).text }}
            </a-tag>
            <a-tag v-if="record.review" :color="reviewStatusMeta(record.review.status).color">
              {{ reviewStatusMeta(record.review.status).text }}
            </a-tag>
          </template>
        </a-table-column>
        <a-table-column title="来源" width="110">
          <template #default="{ record }">
            <a
              v-if="record.article?.source_url"
              :href="record.article.source_url"
              target="_blank"
              rel="noreferrer"
            >
              原文
            </a>
            <span v-else class="placeholder-text">—</span>
          </template>
        </a-table-column>
        <a-table-column title="attempts" width="90" align="center">
          <template #default="{ record }">{{ record.attempts }}</template>
        </a-table-column>
        <a-table-column title="操作" width="200">
          <template #default="{ record }">
            <a-button v-if="record.article" type="link" size="small" @click="openDrawer(record)">
              查看
            </a-button>
            <template v-if="record.review?.status === 'pending_review'">
              <a-button type="link" size="small" @click="confirmApprove(record)">通过</a-button>
              <a-button type="link" danger size="small" @click="openReject(record)">拒绝</a-button>
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
              #{{ (drawer.slot?.slot_index ?? 0) + 1 }}
            </a-descriptions-item>
            <a-descriptions-item label="难度">
              <a-tag :color="DIFFICULTY_COLOR[drawer.slot?.difficulty ?? ''] || 'default'">
                {{ drawer.slot?.difficulty }}
              </a-tag>
            </a-descriptions-item>
            <a-descriptions-item label="日期">{{ drawer.detail.run_date }}</a-descriptions-item>
            <a-descriptions-item label="段落数">{{ drawer.detail.paragraph_count }}</a-descriptions-item>
            <a-descriptions-item label="分类" :span="2">{{ drawer.detail.category }}</a-descriptions-item>
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
              <a-descriptions-item label="时间" :span="2">
                {{ drawer.detail.review.reviewed_at || '—' }}
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
          <a-timeline v-if="drawer.slot && drawer.slot.history.length" class="history-timeline">
            <a-timeline-item v-for="(h, i) in drawer.slot.history" :key="i">
              <div class="history-row">
                <a-tag :color="reviewStatusMeta(h.status).color">
                  {{ reviewStatusMeta(h.status).text }}
                </a-tag>
                <span class="history-article">文章 #{{ h.article_id }}</span>
                <span v-if="h.reviewed_by" class="history-meta">审核人：{{ h.reviewed_by }}</span>
                <span v-if="h.reviewed_at" class="history-meta">时间：{{ h.reviewed_at }}</span>
              </div>
              <div v-if="h.reject_reason" class="history-reason">原因：{{ h.reject_reason }}</div>
            </a-timeline-item>
          </a-timeline>
          <div v-else class="placeholder-text">暂无审核记录</div>

          <!-- pending_review：抽屉内审核/编辑操作 -->
          <div
            v-if="drawer.detail.review?.status === 'pending_review' && !editing.active"
            class="drawer-actions"
          >
            <a-button type="primary" @click="confirmApprove(drawer.slot!)">通过</a-button>
            <a-button danger @click="openReject(drawer.slot!)">拒绝</a-button>
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
.placeholder-text {
  color: #999;
  font-style: italic;
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
