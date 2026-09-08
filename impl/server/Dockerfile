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
# 下载到 ~/.cache/ms-playwright（目录名含 rev，随版本漂移）后**整个目录**拷贝到固定路径——
# 单拷贝二进制会丢配套资源（icudtl.dat / *.pak），Chrome 启动即报 ICU 错误退出。
# 注意：--no-sandbox 由应用侧 backend.argv 传入（src/engine/sites/common.ts），
# 镜像层 shell wrapper 方案已被证伪（sh 进程链致 zygote socket 断开，见 docs §6）。
RUN bunx playwright-core@1.63.0 install-deps chromium-headless-shell \
    && bunx playwright-core@1.63.0 install chromium-headless-shell \
    && mkdir -p /usr/local/bin/chrome-shell-dir \
    && cp -r $(find /root/.cache/ms-playwright -type d -name chrome-headless-shell-linux64 | head -1)/. \
        /usr/local/bin/chrome-shell-dir/

# Bun.WebView 在 Linux 查找浏览器二进制的显式路径；不设则按固定路径探测（探测不到 Shell）
ENV BUN_CHROME_PATH=/usr/local/bin/chrome-shell-dir/chrome-headless-shell

# ... 其余保持不变
COPY --from=backend-deps /app/node_modules ./node_modules
COPY package.json ./
COPY ./src ./src
COPY --from=frontend-builder /app/admin-ui/dist ./admin-ui/dist

EXPOSE 8080
CMD ["bun", "run", "src/main.ts"]