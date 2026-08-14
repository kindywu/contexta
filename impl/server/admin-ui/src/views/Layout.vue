<script setup lang="ts">
import { useRoute, useRouter } from 'vue-router'
import { computed } from 'vue'
import { clearToken } from '../api'

const router = useRouter()
const route = useRoute()

const selectedKey = computed(() => route.path)

function onLogout() {
  clearToken()
  router.replace('/login')
}
</script>

<template>
  <a-layout style="min-height: 100vh">
    <a-layout-sider theme="dark">
      <div class="logo">Contexta 管理后台</div>
      <a-menu theme="dark" mode="inline" :selected-keys="[selectedKey]">
        <a-menu-item key="/users">
          <router-link to="/users">用户管理</router-link>
        </a-menu-item>
        <a-menu-item key="/articles">
          <router-link to="/articles">文章审核</router-link>
        </a-menu-item>
        <a-menu-item key="/usage">
          <router-link to="/usage">用量统计</router-link>
        </a-menu-item>
        <a-menu-item key="/prompts">
          <router-link to="/prompts">Prompt 管理</router-link>
        </a-menu-item>
      </a-menu>
    </a-layout-sider>
    <a-layout>
      <a-layout-header class="header">
        <span class="header-title">{{ route.meta.title || '' }}</span>
        <a-button type="text" class="logout" @click="onLogout">退出登录</a-button>
      </a-layout-header>
      <a-layout-content class="content">
        <router-view />
      </a-layout-content>
    </a-layout>
  </a-layout>
</template>

<style scoped>
.logo {
  color: #fff;
  font-size: 16px;
  font-weight: 600;
  text-align: center;
  line-height: 64px;
  overflow: hidden;
  white-space: nowrap;
}
.header {
  background: #fff;
  padding: 0 24px;
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.header-title {
  font-size: 18px;
  font-weight: 600;
}
.content {
  margin: 24px;
}
</style>
