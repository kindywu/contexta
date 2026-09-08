# ---------- 阶段1：编译前端 ----------
FROM oven/bun:1 AS frontend-builder
WORKDIR /app/admin-ui
COPY ./admin-ui/package.json ./admin-ui/bun.lock ./
RUN bun install --frozen-lockfile
COPY ./admin-ui .
RUN bun run build   # 产出 /app/admin-ui/dist

# ---------- 阶段2：安装后端生产依赖 ----------
FROM oven/bun:1 AS backend-deps
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production   # 关键：只装 production 依赖

# ---------- 阶段3：最终运行镜像 ----------
# Debian 基底（oven/bun:1，glibc）：Bun.WebView 在 Linux 经 CDP 驱动浏览器二进制
# （macOS 才用 WebKit）。Bun 官方支持的搭档是 Playwright 分发的 chrome-headless-shell
# （Bun 文档探测顺序第 5 条；全量 Chromium/Chrome 与 Bun 1.4.2 存在行为差异，勿用）。
FROM oven/bun:1 AS runner
WORKDIR /app

# tzdata（Asia/Shanghai 时区）+ 基础字体
RUN apt-get update && apt-get install -y --no-install-recommends \
        tzdata \
        fonts-liberation \
    && rm -rf /var/lib/apt/lists/* \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

ENV TZ=Asia/Shanghai

# chrome-headless-shell（Bun.WebView 的浏览器后端）+ 其全部动态库依赖（install-deps 自动清单）
# 1) 下载到 ~/.cache/ms-playwright（目录名含 rev，随版本漂移）
# 2) 拷到固定路径 /usr/local/bin/chrome-headless-shell-bin
# 3) wrapper 补 --no-sandbox：root 容器内 Chrome 拒绝启动（sandbox 仅本地桌面场景需要，
#    容器内无沙箱可复用；Bun spawn 不带该参数，见 docs/config-and-deploy.md §6）
RUN bunx playwright-core@1.63.0 install-deps chromium-headless-shell \
    && bunx playwright-core@1.63.0 install chromium-headless-shell \
    && find /root/.cache/ms-playwright -name chrome-headless-shell -type f -exec cp {} /usr/local/bin/chrome-headless-shell-bin \; \
    && chmod +x /usr/local/bin/chrome-headless-shell-bin \
    && printf '#!/bin/sh\nexec /usr/local/bin/chrome-headless-shell-bin --no-sandbox "$@"\n' > /usr/local/bin/chrome-headless-shell \
    && chmod +x /usr/local/bin/chrome-headless-shell

# Bun.WebView 在 Linux 查找浏览器二进制的显式路径（wrapper）；不设则按固定路径探测（探测不到）
ENV BUN_CHROME_PATH=/usr/local/bin/chrome-headless-shell

# ... 其余保持不变
COPY --from=backend-deps /app/node_modules ./node_modules
COPY package.json ./
COPY ./src ./src
COPY --from=frontend-builder /app/admin-ui/dist ./admin-ui/dist

EXPOSE 8080
CMD ["bun", "run", "src/main.ts"]