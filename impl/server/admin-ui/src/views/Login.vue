<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { message } from 'ant-design-vue'
import { api, setToken } from '../api'

const router = useRouter()
const route = useRoute()

const form = reactive({ username: '', password: '' })
const loading = ref(false)

async function onSubmit() {
  if (!form.username || !form.password) {
    message.warning('请输入用户名和密码')
    return
  }
  loading.value = true
  try {
    const { token } = await api.login(form.username, form.password)
    setToken(token)
    message.success('登录成功')
    router.replace((route.query.redirect as string) || '/')
  } catch {
    // 错误提示已在拦截器处理
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login-page">
    <div class="login-card">
      <h1 class="login-title">Contexta 管理后台</h1>
      <a-form layout="vertical" @submit.prevent="onSubmit">
        <a-form-item label="用户名">
          <a-input v-model:value="form.username" placeholder="请输入用户名" autocomplete="username" />
        </a-form-item>
        <a-form-item label="密码">
          <a-input-password
            v-model:value="form.password"
            placeholder="请输入密码"
            autocomplete="current-password"
            @press-enter="onSubmit"
          />
        </a-form-item>
        <a-button type="primary" block html-type="submit" :loading="loading">
          登 录
        </a-button>
      </a-form>
    </div>
  </div>
</template>

<style scoped>
.login-page {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1677ff 0%, #0958d9 100%);
}
.login-card {
  width: 360px;
  padding: 40px 32px;
  background: #fff;
  border-radius: 8px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15);
}
.login-title {
  margin: 0 0 24px;
  font-size: 22px;
  text-align: center;
}
</style>
