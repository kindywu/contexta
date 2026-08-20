<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api, type UsageRow } from '../api'

const loading = ref(false)
const rows = ref<UsageRow[]>([])

async function load() {
  loading.value = true
  try {
    rows.value = await api.usage()
  } catch {
    // 拦截器已提示
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <a-card :loading="loading">
    <a-table :data-source="rows" :pagination="false" row-key="phone" size="middle">
      <a-table-column title="用户" width="200">
        <template #default="{ record }">
          <span v-if="record.phone">{{ record.phone }}</span>
          <a-tag v-else color="purple">服务端任务</a-tag>
        </template>
      </a-table-column>
      <a-table-column title="端点" data-index="endpoint" width="240" />
      <a-table-column title="调用次数" data-index="calls" width="120" />
      <a-table-column title="Prompt Tokens" data-index="prompt_tokens" width="150" />
      <a-table-column title="Completion Tokens" data-index="completion_tokens" />
    </a-table>
  </a-card>
</template>
