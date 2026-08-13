<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { message, Modal } from 'ant-design-vue'
import { api, type AdminUser } from '../api'

const loading = ref(false)
const users = ref<AdminUser[]>([])

// 封禁弹窗
const banState = reactive({
  open: false,
  phone: '',
  reason: '',
  submitting: false,
})

// 配额弹窗（null = 清覆盖，回落全局默认）
const quotaState = reactive({
  open: false,
  phone: '',
  wordDaily: undefined as number | undefined,
  submitting: false,
})

function formatTime(ms: number): string {
  return new Date(ms).toLocaleString('zh-CN', { hour12: false })
}

async function load() {
  loading.value = true
  try {
    users.value = await api.listUsers()
  } catch {
    // 拦截器已提示
  } finally {
    loading.value = false
  }
}

function openBan(user: AdminUser) {
  banState.phone = user.phone
  banState.reason = ''
  banState.open = true
}

async function submitBan() {
  banState.submitting = true
  try {
    await api.banUser(banState.phone, banState.reason)
    message.success(`已封禁 ${banState.phone}`)
    banState.open = false
    await load()
  } catch {
    // 拦截器已提示
  } finally {
    banState.submitting = false
  }
}

function confirmUnban(user: AdminUser) {
  Modal.confirm({
    title: `确认解封 ${user.phone}？`,
    content: '解封后用户可正常使用 App。',
    okText: '解封',
    cancelText: '取消',
    onOk: async () => {
      await api.unbanUser(user.phone)
      message.success(`已解封 ${user.phone}`)
      await load()
    },
  })
}

function openQuota(user: AdminUser) {
  quotaState.phone = user.phone
  quotaState.wordDaily = user.quota_word_daily ?? undefined
  quotaState.open = true
}

async function submitQuota() {
  quotaState.submitting = true
  try {
    // 清空（undefined）→ null：清除覆盖，回落全局默认
    await api.setQuota(quotaState.phone, quotaState.wordDaily ?? null)
    message.success(`已更新 ${quotaState.phone} 的每日配额`)
    quotaState.open = false
    await load()
  } catch {
    // 拦截器已提示
  } finally {
    quotaState.submitting = false
  }
}

onMounted(load)
</script>

<template>
  <a-card :loading="loading">
    <a-table :data-source="users" :pagination="{ pageSize: 20 }" row-key="phone" size="middle">
      <a-table-column title="手机号" data-index="phone" width="160" />
      <a-table-column title="状态" width="90">
        <template #default="{ record }">
          <a-tag :color="record.status === 'banned' ? 'red' : 'green'">
            {{ record.status === 'banned' ? '已封禁' : '正常' }}
          </a-tag>
        </template>
      </a-table-column>
      <a-table-column title="封禁原因" data-index="banned_reason" width="180">
        <template #default="{ record }">
          <span :style="{ color: record.banned_reason ? undefined : '#bbb' }">
            {{ record.banned_reason || '—' }}
          </span>
        </template>
      </a-table-column>
      <a-table-column title="注册时间" width="180">
        <template #default="{ record }">{{ formatTime(record.created_at) }}</template>
      </a-table-column>
      <a-table-column title="今日查词" data-index="today_word_lookups" width="100" />
      <a-table-column title="每日配额" width="100">
        <template #default="{ record }">{{ record.quota_word_daily ?? '默认' }}</template>
      </a-table-column>
      <a-table-column title="操作" width="220">
        <template #default="{ record }">
          <template v-if="record.status === 'normal'">
            <a-button type="link" size="small" danger @click="openBan(record)">封禁</a-button>
            <a-button type="link" size="small" @click="openQuota(record)">改配额</a-button>
          </template>
          <template v-else>
            <a-button type="link" size="small" @click="confirmUnban(record)">解封</a-button>
            <a-button type="link" size="small" @click="openQuota(record)">改配额</a-button>
          </template>
        </template>
      </a-table-column>
    </a-table>
  </a-card>

  <!-- 封禁弹窗 -->
  <a-modal
    v-model:open="banState.open"
    title="封禁用户"
    :confirm-loading="banState.submitting"
    ok-text="确认封禁"
    cancel-text="取消"
    @ok="submitBan"
  >
    <p>用户：{{ banState.phone }}</p>
    <a-textarea
      v-model:value="banState.reason"
      placeholder="封禁原因（可选）"
      :rows="3"
      maxlength="200"
      show-count
    />
  </a-modal>

  <!-- 配额弹窗 -->
  <a-modal
    v-model:open="quotaState.open"
    title="修改每日配额"
    :confirm-loading="quotaState.submitting"
    ok-text="保存"
    cancel-text="取消"
    @ok="submitQuota"
  >
    <p>用户：{{ quotaState.phone }}</p>
    <a-input-number
      v-model:value="quotaState.wordDaily"
      :min="0"
      :precision="0"
      placeholder="留空 = 清除覆盖，回落全局默认"
      style="width: 100%"
    />
    <div class="quota-tip">留空表示不单独覆盖该用户，按系统全局默认配额执行。</div>
  </a-modal>
</template>

<style scoped>
.quota-tip {
  margin-top: 8px;
  font-size: 12px;
  color: #999;
}
</style>
