<script setup lang="ts">
import { onMounted, reactive, ref, computed } from 'vue'
import { message } from 'ant-design-vue'
import { api, type PromptItem } from '../api'

const loading = ref(false)
const prompts = ref<PromptItem[]>([])

// 编辑弹窗
const editState = reactive({
  open: false,
  key: '',
  content: '',
  saving: false,
})

// 服务端 PROMPT_KEYS 白名单（prompt_service.rs）——GET 返回不足 7 项说明 DB 缺行，
// 缺行 key 运行时回落嵌入默认值，页面提示之（C2 遗留）。
const PROMPT_KEYS = [
  'word_lookup_system',
  'word_lookup_user',
  'article_common',
  'article_low',
  'article_medium',
  'article_high',
  'article_user_prompt',
]

const missingCount = computed(
  () => PROMPT_KEYS.filter((k) => !prompts.value.some((p) => p.key === k)).length,
)

// 占位符提示（与 prompts.rs 实际替换逻辑逐 key 对齐）
const PLACEHOLDERS: Record<string, string[]> = {
  word_lookup_user: ['{{word}}'],
  article_user_prompt: ['{{orderIndex}}', '{{category}}'],
  article_common: ['{{title}}'],
  article_low: ['{{title}}'],
  article_medium: ['{{title}}'],
  article_high: ['{{title}}'],
}

function placeholders(key: string): string[] {
  return PLACEHOLDERS[key] ?? []
}

function formatTime(ms: number): string {
  // 0 = 种子默认值（从未被管理端修改）
  if (!ms) return '默认（未修改）'
  return new Date(ms).toLocaleString('zh-CN', { hour12: false })
}

function preview(content: string): string {
  return content.length > 80 ? content.slice(0, 80) + '…' : content
}

async function load() {
  loading.value = true
  try {
    prompts.value = await api.listPrompts()
  } catch {
    // 拦截器已提示
  } finally {
    loading.value = false
  }
}

function openEdit(item: PromptItem) {
  editState.key = item.key
  editState.content = item.content
  editState.open = true
}

function rowClick(record: PromptItem) {
  return { onClick: () => openEdit(record) }
}

async function savePrompt() {
  const content = editState.content.trim()
  if (!content) {
    message.warning('Prompt 内容不能为空')
    return
  }
  editState.saving = true
  try {
    await api.updatePrompt(editState.key, content)
    message.success(`已保存 ${editState.key}`)
    editState.open = false
    await load()
  } catch {
    // 拦截器已提示（400：内容为空 / 未知 key）
  } finally {
    editState.saving = false
  }
}

onMounted(load)
</script>

<template>
  <div class="prompts-page">
    <a-alert
      v-if="missingCount > 0"
      type="warning"
      show-icon
      message="部分 Prompt 缺失，将使用内置默认值"
      :description="`数据库缺少 ${missingCount} 个 Prompt 行（${PROMPT_KEYS.filter((k) => !prompts.some((p) => p.key === k)).join('、')}），运行时回落编译期嵌入默认；可编辑以落库。`"
      class="missing-alert"
    />

    <a-card :loading="loading">
      <a-table
        :data-source="prompts"
        :pagination="{ pageSize: 20 }"
        row-key="key"
        size="middle"
        :custom-row="rowClick"
      >
        <a-table-column title="Key" data-index="key" width="220" />
        <a-table-column title="更新时间" width="200">
          <template #default="{ record }">{{ formatTime(record.updated_at) }}</template>
        </a-table-column>
        <a-table-column title="内容预览" min-width="320">
          <template #default="{ record }">
            <span class="content-preview">{{ preview(record.content) }}</span>
          </template>
        </a-table-column>
        <a-table-column title="操作" width="90">
          <template #default="{ record }">
            <a-button type="link" size="small" @click="openEdit(record)">编辑</a-button>
          </template>
        </a-table-column>
      </a-table>
    </a-card>

    <!-- 编辑弹窗 -->
    <a-modal
      v-model:open="editState.open"
      title="编辑 Prompt"
      :confirm-loading="editState.saving"
      ok-text="保存"
      cancel-text="取消"
      @ok="savePrompt"
    >
      <a-form layout="vertical">
        <a-form-item label="Key">
          <a-input :value="editState.key" disabled />
        </a-form-item>
        <a-form-item label="内容">
          <a-textarea
            v-model:value="editState.content"
            :auto-size="{ minRows: 6, maxRows: 20 }"
            placeholder="Prompt 内容"
          />
        </a-form-item>
      </a-form>
      <div v-if="placeholders(editState.key).length" class="ph-hint">
        可用占位符：
        <template v-for="ph in placeholders(editState.key)" :key="ph">
          <code>{{ ph }}</code>
        </template>
        （保存后由服务端替换，需原样保留）
      </div>
    </a-modal>
  </div>
</template>

<style scoped>
.missing-alert {
  margin-bottom: 16px;
}
.content-preview {
  display: block;
  white-space: pre-line;
  word-break: break-all;
  color: #555;
}
.ph-hint {
  margin-top: 4px;
  font-size: 12px;
  color: #999;
}
.ph-hint code {
  margin: 0 4px;
  padding: 1px 6px;
  background: #f5f5f5;
  border: 1px solid #e8e8e8;
  border-radius: 4px;
  font-size: 12px;
  color: #333;
}
</style>
