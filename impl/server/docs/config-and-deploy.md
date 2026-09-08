# Contexta Server 配置与部署

> 主题文档：环境变量全表（以 `.env.example` 为准）、部署（标准：GitHub Actions + Docker Compose；备选：rsync + bun + systemd）、运维（备份、升级）与已知风险。配套文件：`.github/workflows/deploy-server.yml`（GHA 部署流水线）、`docker-compose.yml`（Compose 编排）、`deploy/contexta-server.service`（备选 systemd unit）。
> **注意**：`deploy/config.yaml.example` 为 Rust 时期遗留对照清单，**已废弃**（现行配置只有环境变量），文件保留待清理，请勿再引用。

## 1. 环境变量全表（`.env`）

**单一 `.env` 文件**（Bun 启动自动加载，无需 dotenv）同时服务引擎（`engine/config.ts` 的 `loadConfig`）与服务端（`config.ts` 的 `loadServerConfig`）——两份 schema 从同一进程环境读取，重叠字段（LLM_*/TIMEZONE/PROXY_URL）两边各自校验。缺省值以两处代码为准；下表"必填"项缺失或非法 → 启动失败（`process.exit(1)`）。

```bash
cp .env.example .env   # 本地开发：填入 LLM_API_KEY 与 JWT_SECRET
```

> **生产服务器不落密钥**（2026-09-08 起）：`/opt/contexta/server/.env` 只含非密钥配置，`LLM_API_KEY` / `JWT_SECRET` / `ADMIN_JWT_SECRET` / `ADMIN_INIT_PASSWORD` 全部由 GHA Secret 注入（见 §3.1）；人工在服务器启动须带键前缀：`LLM_API_KEY=... JWT_SECRET=... ADMIN_JWT_SECRET=... docker compose up -d`（或临时写入 .env）。

| 变量 | 默认值 | 校验 | 说明 |
|---|---|---|---|
| `LLM_API_KEY` | **必填** | 非空 string | 生成与查词共用的 LLM key（缺失启动失败）；**生产经 GHA Secret 注入**（compose `environment` 覆盖 `.env`，见 §3.1），本地可直接填 `.env` |
| `LLM_BASE_URL` | `https://api.deepseek.com` | URL | OpenAI 兼容端点；可换网关 |
| `LLM_MODEL` | `deepseek-v4-flash` | string | 模型名（注意：思考模型 maxTokens 已由代码设为 64000，无需配置） |
| `TIMEZONE` | **必填**（`.env.example` 为 `Asia/Shanghai`） | IANA 名（`Intl` 校验） | 所有日期语义唯一口径；**启动时须与系统时区一致**（`assertSystemTimezone` 硬闸，不一致拒绝运行） |
| `DB_PATH` | `./data/pipeline.sqlite`（`.env.example` 设 `./data/contexta.db`） | string | 业务库：引擎 4 表 + 服务端表 + `article_review` 同库；父目录启动时自动创建 |
| `CHECKPOINT_PATH` | `./data/langgraph.sqlite` | string | LangGraph 检查点库（独立文件；**首次部署需放置可写空文件/目录**，见 §3.5） |
| `OUTPUT_DIR` | `./output` | string | 生成文章的 Markdown 落盘目录（文件名 `run_date-category-<ts>.md`） |
| `BROWSER_CONCURRENCY` | `2` | 正 int | **保留配置**：当前引擎按"每槽一次图运行"执行，站点抓取（Bun.WebView）在节点内按需开合视图，此值尚未被消费（预留） |
| `SLOT_CONCURRENCY` | `5` | 正 int | 每日生成并发槽位数上限（`runPool`）；每槽一条 LangGraph 线程 |
| `PROXY_URL` | 空（不代理） | string | 出站 HTTP 代理（`http://` 形式）；空串转 undefined。作用于 LLM 调用（引擎 `createLLM` 与查词 `driverChat`） |
| `PORT` | `8080` | int 1..65535 | 容器内监听端口（Bun.serve）；宿主经 compose 映射 `443:8080` 对外——安全组放行 443 |
| `JWT_SECRET` | **必填** | ≥32 字符 | HS256 密钥（App 令牌）；`openssl rand -hex 32` 生成；<32 启动失败；**生产经 GHA Secret 注入**（与 ADMIN_JWT_SECRET 同机制，见 §3.1） |
| `ADMIN_JWT_SECRET` | **必填** | ≥32 字符 | admin（Web 管理端）令牌密钥；双密钥鉴权——与 `JWT_SECRET` 分开，App 与 admin 令牌互不交叉；生产经 GHA Secret 注入（同 §3.1） |
| `ADMIN_INIT_PASSWORD` | 空 | string | 设置时启动 seed 管理员 `admin`（argon2id）；已有 admin 行则跳过不覆盖；seed 后可移出 .env；生产可经 GHA Secret 注入（仅新库 seed 生效，同 §3.1） |
| `WORD_QUOTA_DAILY` | `200` | 正 int | 用户每日查词配额（只计真实 LLM 调用；`users.quota_word_daily` 可 per-user 覆盖） |
| `CACHE_TTL_DAYS` | `30` | 正 int | 查词缓存 TTL（命中不调 LLM 不扣配额） |
| `CACHE_MAX_ROWS` | `5000` | 正 int | 查词缓存条数上限（超限删最旧 1 条） |
| `DAILY_GENERATE_WINDOW` | `08:00-08:15` | `HH:MM-HH:MM`（开始必须早于结束） | 每日生成窗口（配置时区当日）：窗口内任意时刻触发，窗口内只生成**当天** 15 篇；错过窗口（进程不在/重启晚于窗口）**跳过不补不重试**——便于本地测试可直接改小/改后 |
| `LLM_TIMEOUT_SECS` | `90` | 正 int | 查词链 LLM 调用硬预算（含 4 次尝试与退避等待；超预算 504 LLM_TIMEOUT） |
| `REGENERATE_LIMIT` | `3` | 正 int | 单槽位拒绝补生成上限：同槽累计 rejected ≥ 上限 → `rejected_final` 不再自动补 |

## 2. 云主机选型

- **推荐**：香港/海外轻量云（免 ICP 备案）+ 域名 + Caddy 自动 HTTPS（App 端明文 HTTP 会被平台限制，HTTPS 必须）。备选：Cloudflare Tunnel（不买域名时）。
- 内存：Bun + SQLite + 每槽 LangGraph（含 WebView 抓取）+ 并发 5 槽，建议 ≥ 2GB（**镜像内置 chrome-headless-shell 支撑 WebView 抓取，见 §6**）。
- 运行时：**Docker + Compose v2**（标准部署路径的唯一宿主要求，见 §3.1）——本机已装 Docker 29.8 + Compose v5.5.1；无需在宿主安装 bun。
- **端口**：容器 8080，宿主映射 `443:8080`——**安全组放行 443** 后 App 即可访问 `http://47.112.20.32:443`（HTTPS / 域名 + Caddy 属下一步，见上）。
- **时区必须设为上海**（`.env` 的 `TIMEZONE` 须与系统时区一致，硬闸）：

```bash
timedatectl set-timezone Asia/Shanghai
timedatectl   # 确认 Local time 为 Asia/Shanghai
```

## 3. 部署

### 3.1 标准流程：GitHub Actions + Docker Compose

**触发**：`push` 到 `main`（仅 `impl/server/**` 或 workflow 文件变更）→ 自动部署；`workflow_dispatch` 手动触发任一分支（预发布验证用）。

**流水线**（`.github/workflows/deploy-server.yml`）：

```
push main（impl/server/** 变更）/ 手动 dispatch
  → [build] buildx 构建 impl/server/Dockerfile（linux/amd64）→ 推 ACR（阿里云个人版）
      crpi-ui1m3okieeg995dg.cn-shenzhen.personal.cr.aliyuncs.com/contexta/contexta:latest-amd64（部署用）+ :1.0-amd64（版本号，见 README 打包约定）
  → [deploy] scp docker-compose.yml → /opt/contexta/server/
             docker compose pull && docker compose up -d
             → 健康检查（curl :443/api/health，30 次 × 2s 重试）失败即报红
```

- **并发互斥**：`concurrency` 同组 `cancel-in-progress: true`——连续 push 只保留最后一个部署，不排队堆积。
- **密钥注入（LLM_API_KEY / JWT_SECRET / ADMIN_JWT_SECRET / ADMIN_INIT_PASSWORD）**：deploy 步骤从 `secrets.*` 以 `KEY='<值>' docker compose up -d` 传入远端（compose `environment` 覆盖 `.env`）；Secret 为空时该键回退 `.env`——本地 `docker compose up` 直跑即后者。更新：`gh secret set <KEY>` → 下一次部署生效。注意：改 `JWT_SECRET` 会使已签发 token 全部失效（需重新登录）；`ADMIN_INIT_PASSWORD` 仅对无 admin 行的新库生效（seed 后该值不再读取）。
- **凭据**：`DEPLOY_SSH_KEY`（服务器 SSH 私钥 = 阿里云 ECS PEM）存 GitHub Repo Secrets；`known_hosts` 指纹内联 workflow 防首次连接 MITM。
- **镜像仓库（ACR 阿里云个人版）**：GHA 用 `ACR_USERNAME` / `ACR_PASSWORD`（Repo Secrets，账号为 `kindywu@aliyun.com`——docker login 用户名须用阿里云账号登录名，勿用其他绑定邮箱）推送；服务器拉取需 `docker login`（2026-09-08 已在服务器 root 侧登录——凭证存 `/root/.docker/config.json`，轮换密码时需重登：`docker login crpi-...aliyuncs.com`）。
  - ⚠️ **ACR 个人版限制**：不接受 OCI attestation（SBOM/provenance）的 empty manifest（`application/vnd.oci.empty.v1+json` → `denied: unknown manifest class`）——构建必须带 `provenance: false` + `sbom: false`（已在 workflow 固定，勿移除）。
- **回滚**：服务器上临时把 `docker-compose.yml` 的 `image:` 改为旧 tag（ACR 上保留各次 `1.0-amd64`/`latest-amd64` 历史版本）→ `docker compose up -d`。
- **GHA 不触碰的数据**：只同步 compose 文件与镜像，`/opt/contexta/server/.env` 与 `data/`、`logs/`、`output/` 留在宿主机（容器 bind mount），重建容器不丢数据。

### 3.2 服务器首次准备（一次性，2026-09-07 已完成于生产服务器 47.112.20.32）

```bash
mkdir -p /opt/contexta/server/{data,logs,output}
touch /opt/contexta/server/data/contexta.db /opt/contexta/server/data/langgraph.sqlite  # 空库
```

- `.env`（权限 600）：**无任何密钥值**（2026-09-08 清空，密钥全由 GHA Secret 注入）；只保留非密钥配置（`TIMEZONE=Asia/Shanghai` 等）。首次建库时如无注入，可用带键前缀的手工命令启动（见 §1 注）。
  > ⚠️ 注意：`.env.example` 曾漏掉必填项 `ADMIN_JWT_SECRET`（双密钥鉴权于 server-auth-and-log 引入），缺它容器反复 exit 1 重启——2026-09-07 已补。
- 服务器 `authorized_keys` 收录 GHA 所用公钥（当前即 ECS PEM 对应公钥）。
- **`LLM_API_KEY` 注入（2026-09-07 起）**：生产 key 存 GitHub Secret `LLM_API_KEY`，GHA deploy 经 compose 注入容器——服务器 `.env` 中该行已注释（注入优先；本地直跑可自行填值）。回退行为同 §3.1。

### 3.3 数据准备（首次部署）

1. **业务库**（`DB_PATH`，如 `data/contexta.db`）——两条路：
   - **A. 导入现有管线数据**（推荐存量）：在本地（或目标机）运行 `tool/import-data.ts`——把文章管线库（旧结构含 `embedding` 列，源库**只读**）导入服务端业务库：备份先行（源 + 旧 target 三件套）→ 拷贝 → **`articles` 去 embedding 重建** → 建表（引擎 4 表 + 服务端表）→ 历史成功槽位全部写 `article_review(status='approved', reviewed_by='import')` → 校验（批次数/行数/段落数/review 行数/integrity_check）。详细契约、校验项与预期报告见 `tool/README.md`。注意：`tool/README.md` 与 `tool/import-data.ts` 头部注释对真实导入路径的约定（如 Rust 遗留 `impl/server/contexta.db` 备份留档）由主会话执行。
     ```bash
     cd impl/server && bun run tool/import-data.ts -- \
       --source <pipeline.sqlite> --target data/contexta.db
     ```
   - **B. 全新空库**（当前生产即此路）：不放置库文件，首次启动时 `ensureSchema` + `ensureServerSchema` 自动幂等建表；文章由每日任务/手动补生成现生成（从 0 开始积累）。
2. **检查点库**（`CHECKPOINT_PATH`，`data/langgraph.sqlite`）：**无需预置内容**——`BunSqliteCheckpointer` 以 `create: true` 打开，文件不存在会自动创建（含 `checkpoints`/`writes` 两表）。放置**空文件**即可（或直接留空不建，首次生成时自动创建）；确认 `data/` 目录可写。
3. **备份留档**：导入脚本每次运行先把源与旧 target 备份到 `<target 同目录>/.backup/`（主文件 + `-wal`/`-shm` 侧车三件套）；生产删除任何备份前先确认对象是本次会话产物，**绝不删除既有备份**。

### 3.4 备选路径：rsync + bun + systemd（非标准，仅直跑需要）

> GHA 上线前的手工部署方式；`deploy/contexta-server.service` 与下述命令保留备查，生产标准见 §3.1。

1. **安装 Bun**：

   ```bash
   curl -fsSL https://bun.sh/install | bash   # 装到 ~/.bun，或按官方文档装到 /usr/local/bin（systemd 用）
   bun --version                              # 确认
   ```

   若 bun 装在用户目录，`/usr/local/bin/bun` 可能与 systemd 的 `ExecStart` 不一致——按实际路径调整 `deploy/contexta-server.service` 的 `ExecStart`。

2. **目录与 .env**（同 §3.2 目录；用户与权限）：

   ```bash
   sudo useradd -r -m -d /opt/contexta contexta   # systemd unit 用 User=contexta
   sudo chown -R contexta:contexta /opt/contexta/server
   sudo rsync -a --exclude node_modules --exclude .git <本地 impl/server>/ /opt/contexta/server/
   cd /opt/contexta/server && sudo -u contexta bun install   # 依赖（bun.lock 锁定）
   sudo -u contexta bash -c 'cp .env.example .env && chmod 600 .env'
   sudo -u contexta edit .env   # 填 LLM_API_KEY / JWT_SECRET（>=32 字符）；核对 TIMEZONE
   ```

3. **systemd 启停**：

   ```bash
   sudo cp deploy/contexta-server.service /etc/systemd/system/contexta-server.service
   sudo systemctl daemon-reload && sudo systemctl enable --now contexta-server
   ```

   unit 语义：`User=contexta` + `WorkingDirectory=/opt/contexta/server`（引擎 `./data`、`./logs`、`./output` 相对该目录）+ `EnvironmentFile=/opt/contexta/server/.env` + `ExecStart=/usr/local/bin/bun run src/main.ts`（TS 直接运行，无构建产物）+ `Restart=on-failure, RestartSec=10`。

### 3.5 日志（Compose 与 systemd 两种视角）

- **服务进程四类日志分离**（`logs/` 相对工作目录，均带日期、**7 天一代自动清理**——启动时 + 每日窗口触发后各清一次）：
  - `logs/server-<YYYY-MM-DD>.log` —— **通用服务**日志（启动/退出/未分流错误等），**同时输出 stdout**——`docker compose logs -f contexta-server`（或 `journalctl -u contexta-server -f`）可见；
  - `logs/app-<YYYY-MM-DD>.log` —— **手机端**请求访问日志（状态码/方法/路径/耗时/打码手机号或 anon），stdout 中**青色**；
  - `logs/admin-<YYYY-MM-DD>.log` —— **Web 管理端**请求访问日志（`/admin` 页面与 `/api/admin/*`），stdout 中**品红色**；
  - `logs/daily-<YYYY-MM-DD>.log` —— **生成**日志（引擎 `log()` + `[daily-task]` 编排行），**只进文件不进 stdout**（与 Web 日志互不干扰）；
  - `logs/run-<时间戳>.log` —— CLI 入口（`bun run daily` / `retry` / `replay`）每次运行一个新文件（`--log-level debug` 记 prompt 全文与 LLM 原始响应；`logs/` 时间戳一律取配置时区）。
- **查看每日任务**：`tail -f /opt/contexta/server/logs/daily-$(date +%F).log`（或直接看 `logs/daily-*.log`）；实时 Web 日志见上。

## 4. 首次启动顺序

1. `.env` 就绪（`LLM_API_KEY` / `JWT_SECRET` / `ADMIN_JWT_SECRET` / `TIMEZONE` 必须；`ADMIN_INIT_PASSWORD` 首次启动设置以 seed `admin`，seed 后可移出）
2. `docker compose up -d`（备选路径为 `systemctl start contexta-server`）—— 启动自动：建库建表 → seed admin → 监听（**启动不生成任何文章**）；每日生成只由窗口循环触发
3. 健康检查：`curl http://localhost:8080/api/health`；管理页 `https://api.example.com/admin`（`admin` + 初始密码）
4. 当天缺文可手动补生成：`POST /api/admin/articles/generate {"date":"2026-08-13"}`（admin JWT）
5. 管理员在管理页**审核**（槽位视图：通过/拒绝/重跑/编辑）——仅已过审对用户可见
6. 此后每日 `DAILY_GENERATE_WINDOW`（默认 `08:00-08:15`，配置时区）内自动生成**当天** 15 篇（三态判定：当天批次已收口 → 跳过；没执行过 → 执行；执行中 → 继续）；错过窗口即跳过，error 槽位由当轮 runFill 自动补跑一次，仍失败留 error 待人工 `POST /api/admin/slots/:id/retry` 或 `bun run retry` 重试

## 5. 运维

### 5.1 备份纪律

- **备份对象 = 两个库各三件套**：`contexta.db`（业务）+ `langgraph.sqlite`（检查点），每库主文件 + `-wal` + `-shm`（WAL 模式，最新写入可能只在侧车——只拷主文件会丢数据）。
- **冷备份**：每月一次，归档到仓库根 `.backup/`（已 gitignore 但按纪律 `git add -f .backup/contexta-db-*` 提交最近一次备份）；删除任何备份前先确认对象是本次会话产物。
- **热备**：`sqlite3 <db> ".backup <路径>"` 或停服拷贝（WAL checkpoint 后三件套齐拷）。
- 恢复：停服 → 三件套回拷（覆盖同名 `-wal`/`-shm`）→ 启动；注意设备端还有 App 本地缓存，恢复服务端会回滚服务端侧数据。

### 5.2 升级（未上线阶段策略：无迁移体系）

- 当前 `tool/db_version` = 0（**从未发布生产**），**没有版本化迁移**：schema 变更直接改 `ensureSchema` / `ensureServerSchema`（全部 `CREATE TABLE/INDEX IF NOT EXISTS`，**代码中无任何 ALTER TABLE**——新增列不自动补到既有库），不存在 001/002 升级链。
- **存量库加列的正确姿势**：新库重建（重新导入/再生成，见下），或用一次性 SQL 补丁脚本（放 `/tmp` 不留仓库）就地 `ALTER TABLE`——模型与 Flutter 端 `tool/migrations/` 的 MIGRATION 纪律一致（发布后才启用编号迁移 + 双写）。
- 未上线期间升级路径（二选一）：
  1. **新库重建**：停服 → 新目录部署新版 → 空库自动建表 → `tool/import-data.ts` 重新导入管线数据（历史文章标 approved）→ 启动；同日之内文章缺失由每日任务/手动补生成补齐。
  2. **就地重启**：同版本小改（无 schema 变更）→ 同步代码 + `bun install` → `systemctl restart contexta-server`（数据文件不动）。
- 任一 schema 变更前：**备份先行**（§5.1 三件套）→ 验证（integrity_check / 表数 / 行数）→ 再重启。
- 若 schema 变更是"发布后"性质（db_version ≥ 1），才启用编号迁移 + drift 双写纪律——当前不适用。

### 5.3 运维速查（标准 = Compose 路径）

```bash
docker compose ps                                          # 服务状态
docker compose logs -f contexta-server                    # 实时日志（Web 服务侧）
tail -f logs/daily-$(date +%F).log                         # 每日任务/生成日志（仅文件）
curl http://localhost:443/api/health                      # 健康检查（宿主 443 → 容器 8080）
docker compose exec contexta-server bun run daily -- --date 2026-08-29    # 手动补生成某日
docker compose exec contexta-server bun run retry -- --date 2026-08-29    # 中断恢复（同 thread 续跑）
docker compose exec contexta-server bun run replay -- --thread daily-2026-08-29-3  # 步骤级重放
docker compose exec contexta-server bun run delete-daily -- --date 2026-08-29 --yes  # 删除某日（先不带 --yes 看预览）
```

> CLI 命令在容器内执行（src 与依赖在镜像内）；`data/`、`logs/` 经 bind mount 共享。备选 systemd 路径等价命令：`journalctl -u contexta-server -f` 与 `sudo -u contexta bun run ...`。

## 6. 已知风险：Bun.WebView 在 Linux 驱动浏览器二进制

- **机制**：站点抓取（`news`/`expository` 两条 pathA 类别）依赖 `Bun.WebView` 打开真实页面（`sites/common.ts` 的 `fetchAnchorSnapshots` / `fetchArticleHTML`）。Bun 1.4+：**macOS 用系统 WebKit；Linux/Windows 经 CDP 驱动浏览器二进制**——不需要 webkit2gtk，也不需要 X/Wayland（无头驱动）。Bun 官方支持的搭档是 **Playwright 分发的 `chrome-headless-shell`**（Bun 文档的二进制探测顺序第 5 条即 Playwright 缓存目录；oven-sh/bun#39819 修的就是 x64 下 Playwright 缓存的自动探测路径——**该修复未并入 1.4.2，必须 `BUN_CHROME_PATH`/`backend.path` 显式指向**）。全量 Chromium/Chrome（如 apt `chromium` 152）与 Bun 1.4.2 存在行为差异（navigate 骨架可走通但会话模型不一致），**勿用**。
- **实况（2026-09-08 生产验证）**：旧镜像 `oven/bun:1-alpine`（Alpine，无浏览器）→ 所有站点报 `Failed to spawn Chrome (set BUN_CHROME_PATH, backend.path, or install Chrome/Chromium)` → `fetchLinks` 全挂 → pathA 槽位 `outcome=error`（9-8 手动补生成即有 3 个槽位因此 error）。
- **修复（已实现，x64 spike + 生产验证）**：Dockerfile 全阶段换 `oven/bun:1`（Debian 基底）；runner 阶段 `bunx playwright-core@1.63.0 install chrome-headless-shell`（`install-deps` 自动补全动态库）；**整目录拷贝**到固定路径 `/usr/local/bin/chrome-shell-dir/`（只拷单个二进制会丢 `icudtl.dat`/`*.pak` 配套资源，Chrome 启动即报 `Invalid file descriptor to ICU data received` 退出）；`ENV BUN_CHROME_PATH=/usr/local/bin/chrome-shell-dir/chrome-headless-shell` 直连真二进制。**`--no-sandbox` 由应用侧 `backend.argv` 传入**（`sites/common.ts` 的 `webViewOptions()`，仅 Linux 生效——macOS 保持 WKWebView）。spike 结果：`evaluate("1+1")=2`，navigate 冒烟通过（x64 实验容器 + 生产容器双通道确认）。
- **⚠️ 已证伪方案（勿回退）**：为 `--no-sandbox` 在镜像层包 shell wrapper 脚本——Bun spawn 经由 `/bin/sh` 进程链后 **zygote socket 断开**（`Failed to send GetTerminationStatus message to zygote` / `Socket closed prematurely`），Chrome 启动失败。`--no-sandbox` 只能走 `backend.argv`（Bun 官方 spawn 通道）。
- **⚠️ 行为注意**：Chrome 后端下 `evaluate()` 必须先有页面 target——**先 `navigate()`（或构造函数传 `url`）后 `evaluate()` 才可用**，否则报 `'Runtime.evaluate' wasn't found`。应用侧 `fetchAnchorSnapshots` 恰是先 `navigateLite` 再取快照，满足前置条件；改动抓取层时序时务必保留该顺序。
- **部署后验证 spike**（每次升级镜像后执行一次；注意先 navigate）：`docker compose exec contexta-server bun -e 'const v = new Bun.WebView({width:1440,height:2000}); await v.navigate("data:text/html,<h1>ok</h1>"); console.log(await v.evaluate("1+1")); v.close()'`——期望输出 `2`。
- **仍未覆盖的风险**：chrome-headless-shell rev 随 `playwright-core@1.63.0` 锁定（升级版本需重新 spike）；站点反爬（CDN/风控）可能导致列表为空——届时按下面降级路径处置。
- **备选方案（必要时按 spike 结果选一）**：
  - 站点不支持时降级：`sites.config.ts` 去掉 chinadaily/tencent 配置行 → `news`/`expository` 变 pathB（模型知识生成，**失去事实锚定，有幻觉风险**——仅作临时降级，须人工审核把关）；
  - 改造抓取层为 HTTP 抓取（属代码改动，另行决策）。
- 若部署后 LLM 欠费/站点全挂：槽位 error 不阻塞服务，恢复后每日任务自动补跑 + 人工 retry/手动补生成即可自愈。

## 7. 部署约束快速索引（实现已裁决，改部署/客户端前必读）

| # | 约束 | 裁决语义 | 出处 |
|---|---|---|---|
| 1 | **difficulty 字典序** | 下发排序 `ORDER BY difficulty, order_index`——TEXT 按 ASCII 字典序（HIGH < LOW < MEDIUM），非自然难度序；App 端自行整理 | `article_reader.ts` |
| 2 | **非法日期 = 空结果** | 下发 `?date=` 非法/任意字符串不校验、不 400，200 空数组；仅管理端补生成严格 ISO 校验 | `routers/articles.ts`、`routers/admin.ts` |
| 3 | **JWT_SECRET ≥ 32 字符** | 启动硬校验，不足报错退出 | `config.ts` |
| 4 | **TZ 影响日界** | 查词配额日界、文章日界、`/today`、日志时间戳全部按配置时区；`TIMEZONE` 与系统时区不一致**拒绝运行** | `engine/config.ts` `assertSystemTimezone` |
| 5 | **error_code 表** | 错误语义固定 `{code, message, error_code}`，HTTP 状态码表达类别、error_code 细分；**新增错误必须走该表** | `response.ts`，见 architecture.md §7 |
| 6 | **窗口触发** | 每日生成 = `DAILY_GENERATE_WINDOW`（默认 08:00-08:15，配置时区）窗口内任意时刻；只生成当天，错过跳过不补；生成日志只进 `logs/daily-*.log` | `services/daily_task.ts`、`config.ts` |
| 7 | **admin 12h TTL** | admin token 12 小时（App token 30 天） | `jwt.ts` |
| 8 | **免密直登** | App 登录不校验验证码（beta 简化），保留 `code` 字段；风险靠封禁兜底 | `services/auth_service.ts` |
| 9 | **文章为全局共享池** | 同难度用户读同批文章（3 难度 × 5 篇/天）；下发需 JWT，与查词配额无关 | 设计决策 |
| 10 | **source_url 不下发** | 文章 App 契约不含 `source_url`（仅管理端可见）；`regenerate_count`/`order_index` 为派生字段 | `article_reader.ts` |
