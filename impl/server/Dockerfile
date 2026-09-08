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
# Debian 基底（oven/bun:1 = Debian bookworm，glibc）：Bun.WebView 在 Linux 经由 CDP
# 驱动 Chrome/Chromium（1.4+；macOS 才用 WebKit），必须装 Chromium 才能抓取新闻源。
FROM oven/bun:1 AS runner
WORKDIR /app

# tzdata（Asia/Shanghai 时区）+ Chromium（Bun.WebView 后端，含全部库依赖）+ 基础字体
RUN apt-get update && apt-get install -y --no-install-recommends \
        tzdata \
        chromium \
        fonts-liberation \
    && rm -rf /var/lib/apt/lists/* \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

ENV TZ=Asia/Shanghai
# Bun.WebView 在 Linux 找 Chrome/Chromium 的默认位置（无该变量时 Bun 按固定路径探测）
ENV BUN_CHROME_PATH=/usr/bin/chromium

# ... 其余保持不变
COPY --from=backend-deps /app/node_modules ./node_modules
COPY package.json ./
COPY ./src ./src
COPY --from=frontend-builder /app/admin-ui/dist ./admin-ui/dist

EXPOSE 8080
CMD ["bun", "run", "src/main.ts"]