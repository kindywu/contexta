import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// base = '/admin/'：与服务端 rust-embed 挂载路径一致（/admin → dist/index.html）。
export default defineConfig({
  plugins: [vue()],
  base: '/admin/',
  build: {
    outDir: 'dist',
  },
  server: {
    port: 5173,
  },
})
