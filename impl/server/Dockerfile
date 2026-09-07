# ---------- 阶段1：编译前端 ----------
FROM oven/bun:1-alpine AS frontend-builder
WORKDIR /app/admin-ui
COPY ./admin-ui/package.json ./admin-ui/bun.lock ./
RUN bun install --frozen-lockfile
COPY ./admin-ui .
RUN bun run build   # 产出 /app/admin-ui/dist

# ---------- 阶段2：安装后端生产依赖 ----------
FROM oven/bun:1-alpine AS backend-deps
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production   # 关键：只装 production 依赖

# ---------- 阶段3：最终运行镜像 ----------
FROM oven/bun:1-alpine AS runner
WORKDIR /app

# 安装 tzdata 并设置系统时区为 Asia/Shanghai
RUN apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

ENV TZ=Asia/Shanghai

# ... 其余保持不变
COPY --from=backend-deps /app/node_modules ./node_modules
COPY package.json ./
COPY ./src ./src
COPY --from=frontend-builder /app/admin-ui/dist ./admin-ui/dist

EXPOSE 8080
CMD ["bun", "run", "src/main.ts"]