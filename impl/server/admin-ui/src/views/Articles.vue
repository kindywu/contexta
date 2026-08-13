<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { message, Modal } from 'ant-design-vue'
import dayjs, { type Dayjs } from 'dayjs'
import { api, type ArticleItem, type ArticleParagraph } from '../api'

const loading = ref(false)
const articles = ref<ArticleItem[]>([])

// 筛选
const filters = reactive({
  status: undefined as string | undefined,
  date: undefined as Dayjs | undefined,
})

// 详情抽屉
const drawer = reactive({
  open: false,
  loading: false,
  item: null as ArticleItem | null,
  paragraphs: [] as ArticleParagraph[],
})

// 拒绝弹窗
const rejectState = reactive({
  open: false,
  id: 0 as number | null,
  reason: '',
  submitting: false,
})

// 手动生成
const generateState = reactive({
  date: undefined as Dayjs | undefined,
  running: false,
})

const STATUS_OPTIONS = [
  { value: '', label: '全部' },
  { value: 'pending_review', label: '待审核' },
  { value: 'approved', label: '已通过' },
  { value: 'rejected', label: '已拒绝' },
  { value: 'rejected_final', label: '已拒绝（终）' },
  { value: 'failed', label: '生成失败' },
]

const DIFFICULTY_COLOR: Record<string, string> = {
  easy: 'green',
  medium: 'orange',
  hard: 'red',
}

function fmtDate(d: Dayjs | undefined): string {
  return d ? d.format('YYYY-MM-DD') : ''
}

// title 空（null/空串）= 预占/生成中/失败，无内容
function hasContent(item: ArticleItem): boolean {
  return !!item.title
}

function statusText(item: ArticleItem): string {
  if (!hasContent(item)) return item.status === 'failed' ? '生成失败' : '生成中'
  switch (item.status) {
    case 'approved':
      return '已通过'
    case 'rejected':
      return '已拒绝'
    case 'rejected_final':
      return '已拒绝（终）'
    default:
      return '待审核'
  }
}

function statusColor(item: ArticleItem): string {
  if (!hasContent(item)) return item.status === 'failed' ? 'volcano' : 'processing'
  switch (item.status) {
    case 'approved':
      return 'green'
    case 'rejected':
      return 'orange'
    case 'rejected_final':
      return 'red'
    default:
      return 'blue'
  }
}

async function load() {
  loading.value = true
  try {
    articles.value = await api.listArticles(
      filters.status || undefined,
      fmtDate(filters.date) || undefined,
    )
  } catch {
    // 拦截器已提示
  } finally {
    loading.value = false
  }
}

function onFilterChange() {
  load()
}

async function openDrawer(item: ArticleItem) {
  drawer.item = item
  drawer.paragraphs = []
  drawer.open = true
  drawer.loading = true
  try {
    const detail = await api.articleDetail(item.id)
    // 后端 paragraphs 是 [[order_index, en, zh], ...] 元组数组，转对象形态
    drawer.paragraphs = (detail.paragraphs ?? []).map(
      (p: [number, string, string]) => ({
        order_index: p[0],
        english_text: p[1],
        chinese_translation: p[2],
      }),
    )
  } catch {
    // 拦截器已提示
  } finally {
    drawer.loading = false
  }
}

async function approve(item: ArticleItem) {
  await api.approveArticle(item.id)
  message.success(`已通过《${item.title}》`)
  drawer.open = false
  await load()
}

function openReject(item: ArticleItem) {
  rejectState.id = item.id
  rejectState.reason = ''
  rejectState.open = true
}

async function submitReject() {
  if (rejectState.id == null) return
  rejectState.submitting = true
  try {
    await api.rejectArticle(rejectState.id, rejectState.reason)
    message.success('已拒绝，将触发补生成')
    rejectState.open = false
    drawer.open = false
    await load()
  } catch {
    // 拦截器已提示
  } finally {
    rejectState.submitting = false
  }
}

// 手动生成：15 篇可达分钟级，按钮 loading 防重复提交；服务端幂等（预占行模式）
async function generate() {
  const date = fmtDate(generateState.date)
  if (!date) {
    message.warning('请先选择日期')
    return
  }
  generateState.running = true
  try {
    await api.generateArticles(date)
    message.success(`已提交 ${date} 的文章生成`)
    await load()
  } catch {
    // 拦截器已提示（含 5 分钟超时）
  } finally {
    generateState.running = false
  }
}
</script>

<template>
  <div class="articles-page">
    <a-card class="filter-card">
      <div class="filter-row">
        <a-select
          v-model:value="filters.status"
          :options="STATUS_OPTIONS"
          style="width: 180px"
          placeholder="状态"
          @change="onFilterChange"
        />
        <a-date-picker
          v-model:value="filters.date"
          placeholder="按日期筛选"
          allow-clear
          style="width: 180px"
          @change="onFilterChange"
        />
        <span class="spacer" />
        <span class="generate-label">手动生成：</span>
        <a-date-picker v-model:value="generateState.date" placeholder="选择日期" />
        <a-button
          type="primary"
          :loading="generateState.running"
          :disabled="!generateState.date"
          @click="generate"
        >
          生成文章
        </a-button>
      </div>
    </a-card>

    <a-card :loading="loading" class="list-card">
      <a-table :data-source="articles" :pagination="{ pageSize: 20 }" row-key="id" size="middle">
        <a-table-column title="日期" data-index="target_date" width="110" />
        <a-table-column title="难度" width="80">
          <template #default="{ record }">
            <a-tag :color="DIFFICULTY_COLOR[record.difficulty] || 'default'">
              {{ record.difficulty }}
            </a-tag>
          </template>
        </a-table-column>
        <a-table-column title="分类" data-index="content_category" width="100" />
        <a-table-column title="标题" min-width="220">
          <template #default="{ record }">
            <span v-if="hasContent(record)">{{ record.title }}</span>
            <span v-else class="placeholder-text">
              {{ record.status === 'failed' ? '生成失败' : '生成中…' }}
            </span>
          </template>
        </a-table-column>
        <a-table-column title="状态" width="130">
          <template #default="{ record }">
            <a-tag :color="statusColor(record)">{{ statusText(record) }}</a-tag>
          </template>
        </a-table-column>
        <a-table-column title="补生成" width="90">
          <template #default="{ record }">{{ record.regenerate_count }}</template>
        </a-table-column>
        <a-table-column title="操作" width="190">
          <template #default="{ record }">
            <a-button type="link" size="small" @click="openDrawer(record)">查看</a-button>
            <a-button
              type="link"
              size="small"
              :disabled="!hasContent(record) || record.status !== 'pending_review'"
              @click="approve(record)"
            >
              通过
            </a-button>
            <a-button
              type="link"
              size="small"
              danger
              :disabled="!hasContent(record) || record.status !== 'pending_review'"
              @click="openReject(record)"
            >
              拒绝
            </a-button>
          </template>
        </a-table-column>
      </a-table>
    </a-card>

    <!-- 详情抽屉 -->
    <a-drawer
      v-model:open="drawer.open"
      :width="720"
      :title="drawer.item?.title || '文章详情'"
    >
      <template v-if="drawer.item">
        <a-descriptions :column="3" size="small" bordered class="drawer-meta">
          <a-descriptions-item label="日期">{{ drawer.item.target_date }}</a-descriptions-item>
          <a-descriptions-item label="难度">{{ drawer.item.difficulty }}</a-descriptions-item>
          <a-descriptions-item label="分类">{{ drawer.item.content_category }}</a-descriptions-item>
          <a-descriptions-item label="状态">
            <a-tag :color="statusColor(drawer.item)">{{ statusText(drawer.item) }}</a-tag>
          </a-descriptions-item>
          <a-descriptions-item label="序号">{{ drawer.item.order_index }}</a-descriptions-item>
          <a-descriptions-item label="补生成次数">
            {{ drawer.item.regenerate_count }}
          </a-descriptions-item>
        </a-descriptions>

        <a-spin :spinning="drawer.loading">
          <div v-if="!hasContent(drawer.item)" class="no-content">
            {{ drawer.item.status === 'failed' ? '该篇生成失败，无内容可审。' : '该篇仍在生成中，暂无内容。' }}
          </div>
          <div v-else class="paragraph-list">
            <div
              v-for="p in drawer.paragraphs"
              :key="p.order_index"
              class="paragraph-item"
            >
              <div class="para-en">
                <span class="para-no">{{ p.order_index }}.</span>
                {{ p.english_text }}
              </div>
              <div class="para-zh">{{ p.chinese_translation }}</div>
            </div>
          </div>
        </a-spin>

        <div
          v-if="hasContent(drawer.item) && drawer.item.status === 'pending_review'"
          class="drawer-actions"
        >
          <a-button
            type="primary"
            :loading="drawer.loading"
            @click="approve(drawer.item!)"
          >
            通过
          </a-button>
          <a-button danger @click="openReject(drawer.item!)">拒绝</a-button>
        </div>
      </template>
    </a-drawer>

    <!-- 拒绝弹窗 -->
    <a-modal
      v-model:open="rejectState.open"
      title="拒绝文章"
      :confirm-loading="rejectState.submitting"
      ok-text="确认拒绝"
      cancel-text="取消"
      @ok="submitReject"
    >
      <p>拒绝后该篇标记为「已拒绝」，并自动触发补生成（未达上限时）。</p>
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
.paragraph-list {
  max-height: 55vh;
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
