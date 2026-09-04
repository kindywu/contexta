# Contexta Server

Contexta 英语学习 App 的服务端（Bun/TS）：LLM API key 只存服务端，提供查词兜底（含配额/缓存/用量账本）与**每日文章生成**（LangGraph 引擎 + LangGraph checkpoint 断点续跑）+ 管理员审核（槽位视图）+ App 每日同步。单进程部署（Hono + 静态托管 Vue3 管理页）。

> 技术栈：Bun + Hono 4 + `bun:sqlite`（WAL）+ LangGraph/LangChain + jsonwebtoken（HS256）+ zod。TS 直接运行，无编译步骤。架构见 [docs/architecture.md](docs/architecture.md)，配置与部署见 [docs/config-and-deploy.md](docs/config-and-deploy.md)。

## 快速启动

```bash
cd impl/server

# 依赖安装
bun install

# 配置：复制 .env.example 并填入必填项
cp .env.example .env
# 必填：LLM_API_KEY、JWT_SECRET（>=32 字符，openssl rand -hex 32）、TIMEZONE（须与系统时区一致）
# 首次启动建议设 ADMIN_INIT_PASSWORD（seed 管理员 admin 后可移除）

# 启动
bun run src/main.ts
```

启动后：
- 健康检查：`GET http://localhost:8080/api/health` → `{"code":0,"data":{"status":"ok"}}`
- 管理页：`http://localhost:8080/admin`（首次启动前设 `ADMIN_INIT_PASSWORD` 即 seed 管理员 `admin`）
- 启动自动：建库建表（幂等）→ seed admin → 监听服务（**启动不生成文章**）；每日 `DAILY_GENERATE_WINDOW`（默认 08:00-08:15）窗口内自动生成**当天** 15 篇，错过窗口跳过不补；生成日志 `logs/daily-<日期>.log`，请求访问日志按面分流 `logs/app-<日期>.log`（手机端）/ `logs/admin-<日期>.log`（管理端），通用服务日志 `logs/server-<日期>.log`（均 7 天轮转；stdout 中 app 青色 / admin 品红）
- 时区硬闸：`TIMEZONE` 与系统当前时区不一致 → 启动失败（`timedatectl set-timezone Asia/Shanghai`）

## 测试

```bash
bun test tests/*.test.ts              # 顶层确定性子集：113 用例，全绿
bun test                              # 全量（含 tests/engine/）：218 用例
bunx tsc --noEmit -p tsconfig.json   # 类型校验（bun run typecheck）
```

- 顶层子集（`tests/*.test.ts`）113 用例全绿：内存 SQLite + 注入假 LLM，不真调模型。
- **全量 `bun test` 含已知预存失败**（源仓库遗留，与本迁移无关，未修复）：
  - `tests/engine/sites.test.ts` — 3 例确定性失败：`extractChinaDailyLinks` 的"近 30 天"新鲜度窗口 vs 2026-08 夹具日期，随日期推移夹具老化永远空列表；
  - `tests/engine/db.test.ts` — 1 例确定性失败：`ensureSchema` 旧库补 `thread_id` 列断言（当前实现无 ALTER TABLE，属遗留待办）；
  - 其余约 16 例为 `.env` 门控：用例装载即调 `loadConfig()`（要求 `LLM_API_KEY`/`TIMEZONE`），本地 `.env` 未提供时失败/报错——配置完整 `.env` 后应转绿；其中 `generate-union-real.test.ts` 为文件级未处理错误（Bun 将其计入 error）。

## CLI 入口（引擎手工运维）

均从 `src/engine/` 直接运行，需先配置 `.env`：

```bash
bun run daily -- --date 2026-08-29 [--log-level debug]   # 每日生成（幂等：批次/槽位/文章/段落入库 + 收口）
bun run retry -- --date 2026-08-29 [--concurrency N]     # 中断恢复：pending 槽位同 thread 续跑 / checkpoint 终态同步
bun run replay -- --thread daily-2026-08-29-3 [--mode generate|validate] [--fresh]   # 步骤级重放（被拒后人工处置）
bun run delete-daily -- --date 2026-08-29 --yes          # 删除某日（业务库 + 该日 checkpoint；先不带 --yes 看预览）
```

## 目录速览

```
impl/server/
  src/
    main.ts                    # 组装：配置+时区硬闸 → 建库建表 → seed admin → 路由 → serve → 每日任务 → 优雅退出
    config.ts / db.ts          # 服务端配置（zod）/ 服务端表 DDL（幂等）+ admin seed 与校验
    auth.ts / jwt.ts           # 认证提取器（封禁/会话/角色）/ JWT 签发校验（App 30d、admin 12h）
    response.ts                # 统一 envelope（{code,message,error_code}）+ ApiError 工厂
    routers/                   # HTTP 层：health / auth / llm / articles / admin
    services/                  # 业务层：auth / llm（查词网关）/ admin / admin_articles / review（审核状态机）/ article_delivery（投放）/ article_reader（投放映射）/ daily_task（每日任务）
    llm/                       # 查词网关侧：retry（callWithRetry + driverChat）/ prompt / lookup_parser
    engine/                    # 文章生成引擎（LangGraph 图 + graph/daily 编排 + sites 抓取 + render + CLIs）
  admin-ui/                    # Vue3 + antd 管理页（构建产物 dist/ 随仓库提交，服务端静态托管）
  deploy/                      # contexta-server.service（Bun 版 systemd unit）；config.yaml.example 已废弃
  tool/                        # import-data.ts（pipeline 库 → 服务端库导入，含备份/去 embedding/校验）
  docs/                        # 架构与部署运维主题文档
  tests/                       # bun test 测试（顶层 + tests/engine/）
```

> 注：`src/` 下仍有 Rust 时期遗留的 `*.rs` 文件（Cargo 栈），**仅历史留档**——现行实现为 TS，待主会话确认后删除；文档一律以 TS 代码为准。
