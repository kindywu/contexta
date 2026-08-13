import { createRouter, createWebHistory } from 'vue-router'
import { getToken } from './api'
import Login from './views/Login.vue'
import Layout from './views/Layout.vue'
import Users from './views/Users.vue'
import Articles from './views/Articles.vue'
import Usage from './views/Usage.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL), // '/admin/'
  routes: [
    { path: '/login', name: 'login', component: Login },
    {
      path: '/',
      component: Layout,
      redirect: '/users',
      children: [
        { path: 'users', name: 'users', component: Users, meta: { title: '用户管理' } },
        { path: 'articles', name: 'articles', component: Articles, meta: { title: '文章审核' } },
        { path: 'usage', name: 'usage', component: Usage, meta: { title: '用量统计' } },
      ],
    },
    { path: '/:pathMatch(.*)*', redirect: '/users' },
  ],
})

// 路由守卫：无 token → /login
router.beforeEach((to) => {
  if (to.path !== '/login' && !getToken()) {
    return { path: '/login', query: { redirect: to.fullPath } }
  }
  if (to.path === '/login' && getToken()) {
    return { path: '/' }
  }
  return true
})

export default router
