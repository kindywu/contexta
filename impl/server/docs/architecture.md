# Contexta Server 架构

> 主题文档：服务端（`impl/server/`）整体架构——分层、模块职责、文章管道状态机、统一 envelope 与 error_code。按实际实现描述（任务 T1-T14 后的最终状态）。

## 1. 系统总览

Contexta Server 是 Contexta 英语学习 App 的 Rust 服务端：DeepSeek API key 只存在于服务端；查词兜底与手动加词（LLM 领域端点）服务端化；**文章生成管道整体移服务端**（每日定时生成 + 管理员审核 + App 每日同步），App 本地数据库退化为服务端前的缓存层。

```mermaid
flowchart TB
    subgraph app["Flutter App（学习链路）"]
        A1["查词链: LRU→DB→解析→远程LLM"]
        A2["文章: 每日同步 → 本地批次库"]
        A3["阅读/学习记录/本地TTS"]
    end

    subgraph server["服务端 axum（云主机，单二进制）"]
        R["routers（HTTP 层）<br/>auth / admin / llm / articles / health"]
        S["services（业务层）<br/>auth_service / llm_service / article_service / admin_service / source_service"]
        T["tasks（定时任务）<br/>article_daily_task：每日生成"]
        D["drivers（驱动层）<br/>SQLite (sqlx) + DeepSeek (reqwest) + 事实源 chinadaily (HTML)"]
        UI["admin-ui（Vue3 + antd，rust-embed 嵌入）"]
    end

    app -- "TLS + JWT" --> R
    R --> S
    S --> D
    T --> S
    T --> D
    R --> UI
```

- **技术栈**：axum 0.8 + tokio + sqlx 0.9（SQLite，WAL + foreign_keys ON）+ reqwest（DeepSeek、chinadaily 事实源抓取）+ jsonwebtoken（HS256）+ argon2（admin 密码）
- **分层纪律**：`handler → services → drivers` 单向依赖，后台任务走 `tasks/` 模块（进程内定时器，无需外部 cron）
- **单二进制部署**：admin-ui 构建产物（`admin-ui/dist/`）经 rust-embed 编译进二进制，`cargo build --release` 产出唯一 `server` 可执行文件

## 2. 目录结构与模块职责

```
impl/server/
  src/
    main.rs                    # 启动：配置 → 连库 → 迁移 → seed admin → 路由 → 每日任务 → 优雅监听
    lib.rs                     # 库目标：AppState（pool + cfg）+ build_router / make_router
    config.rs                  # 环境变量配置加载（含 JWT_SECRET>=32 硬校验）
    response.rs                # 统一 envelope（ApiResult / ApiErrorBody）+ AppError → HTTP 映射
    db.rs                      # SQLite 连接池（WAL/FK）+ 001 幂等迁移 + seed_admin（argon2）
    extractors.rs              # AuthUser（App JWT + 封禁 + 会话校验）/ AdminAuth（role: admin）
    jwt.rs                     # App token 30 天 / Admin token 12 小时；iat == issued_at 精确校验
    static.rs                  # 管理页静态资源（rust-embed 嵌入 admin-ui/dist/）
    drivers/
      deepseek.rs              # DeepSeek HTTP 客户端 + call_with_retry（重试/退避/预算）
      chinadaily.rs            # 事实源驱动：SourceFetcher trait / ChinadailyFetcher（HTML 抓取）/ NoopFetcher（降级）
    llm/
      parser.rs                # XML 解析（WordLookup / ArticleDraft，容错兜底对齐 Dart 版）
    prompts.rs                  # prompt 构建（内容唯一来源 = DB prompt 表，管理端可编辑）
    routers/                   # HTTP 层：health / auth / admin / llm / articles（见 §3）
    services/                  # 业务层：auth / llm（含配额/缓存）/ article（状态机）/ admin / source（事实源）
      source_service.rs        # 事实源：store_sources 入库幂等 / pick_source 选源预占（见 §5.5）
    tasks/
      article_daily_task.rs    # 每日生成任务（启动补漏 + 定时循环，见 §5.1）
  tests/                       # 集成测试（内存 SQLite + httpmock mock DeepSeek）
  admin-ui/                    # Vue3 + antd 管理页（dist 随二进制发布）
  deploy/                      # contexta-server.service + config.yaml.example
  docs/                        # 本目录（架构 / 部署运维）
  tool/
    db_version                 # 0 = 服务端从未发布生产
    migrations/001-init.sql    # 0→1 init（开发期活版本，全部 IF NOT EXISTS 幂等）
```

| 模块 | 职责要点 |
|---|---|
| `config.rs` | 全部配置走环境变量（无 config.yaml 读取路径；`deploy/config.yaml.example` 是部署时的 env 对照清单）。`JWT_SECRET`（≥32 字符）与 `DEEPSEEK_API_KEY` 缺失即启动失败 |
| `response.rs` | 成功 `{code:0, data}`；失败 `{code, message, error_code}`，HTTP 状态码表达错误类别（见 §6 错误语义） |
| `jwt.rs` | App token 30 天（`APP_TOKEN_TTL_SECS`），admin token **12 小时**（`ADMIN_TOKEN_TTL_SECS`，缩短暴露窗口）。App token 的 `iat` 与会话行 `issued_at`（毫秒）**精确相等**——重登刷新 issued_at 即令旧 token 失效 |
| `extractors.rs` | `AuthUser`：校验 JWT → 先封禁后会话（被封禁得 403 BANNED 而非 401 EVICTED）→ `iat == issued_at` 精确匹配，行不存在（登出/被挤掉）或落后一律 401 EVICTED。`AdminAuth`：校验 admin JWT + `role == "admin"` |
| `drivers/deepseek.rs` | `call_with_retry`：共 4 次尝试；429 用 Retry-After（clamp 0..30s），其余可恢复错误指数退避 `2s × 2^(n-1)` 封顶 10s；总时长受 `LLM_TIMEOUT_SECS` 预算约束（退避等待也计入） |
| `drivers/chinadaily.rs` | 事实源驱动：`SourceFetcher` trait（`fetch_recent`）/ `ChinadailyFetcher`（china+world 栏目 HTML 抓取，URL 路径日期判断新鲜度窗口）/ `NoopFetcher`（构造失败降级恒返回空）；纯解析 `parse_list_links` / `parse_article_page` 与 HTTP IO 分离（fixture 可测，见 §5.5） |
| `llm/parser.rs` | 解析 DeepSeek XML 响应为 `WordLookup` / `ArticleDraft`；容错兜底（非法根标签/缺失字段/多义项）与 Dart 版逐用例对齐 |
| `services/llm_service.rs` | 查词链：normalize 小写 → 缓存命中直返（TTL 30 天、上限 5000 条，超限删最旧）→ 配额检查（真实 LLM 调用计数）→ DeepSeek → 解析 → 写缓存 → 记 usage_log。文章内容生成复用同一驱动 |
| `services/article_service.rs` | 文章生成/审核状态机、每日预算、预占行模式（见 §5） |
| `services/source_service.rs` | 事实源服务：`store_sources`（INSERT OR IGNORE 幂等入库）/ `pick_source`（单语句条件更新预占 + 池空抓取补充 + 失败降级，见 §5.5） |
| `services/auth_service.rs` | 免密直登（预留 `code` 字段）：phone + deviceId → 自动注册 → 会话表挤掉至多 2 个活跃会话（按 issued_at 最旧让位）→ 签发 token |
| `tasks/article_daily_task.rs` | 启动补漏（今天+明天）+ 每日定时生成循环（见 §5.1） |

## 3. 端点清单（以 routers 为准）

### 应用端（App JWT 保护，`AuthUser`）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/auth/login` | 手机号直登（`{phone, deviceId, code?}`）→ `{token, expires_at}`；自动注册、2 设备挤掉 |
| POST | `/api/auth/logout` | 删除会话行 |
| GET | `/api/auth/me` | 返回 `{phone}` |
| POST | `/api/llm/word-lookup` | `{word}` → WordDetail JSON（查词兜底） |
| GET | `/api/articles/today` | 当天全部已过审文章（Local 时区当天） |
| GET | `/api/articles?date=YYYY-MM-DD` | 指定日期（无 date 默认今日）；**非法日期 → 200 空结果**（不 400） |

### 管理员（admin JWT 保护，`AdminAuth`）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/admin/login` | username + password（argon2）→ `{token}` |
| GET | `/api/admin/users` | 用户列表（含每人今日查词次数） |
| POST | `/api/admin/users/{phone}/ban` | 封禁（附 reason） |
| POST | `/api/admin/users/{phone}/unban` | 解封 |
| PUT | `/api/admin/users/{phone}/quota` | 查词配额覆盖（null 清覆盖回落全局默认） |
| GET | `/api/admin/usage` | 今日用量汇总（按 phone × endpoint 聚合 token） |
| GET | `/api/admin/articles` | 文章列表（date/status 可选过滤，白名单列 + 全绑参；含事实源链接 `source_url`） |
| GET | `/api/admin/articles/{id}` | 文章详情（段落已拆分英文/中文；含事实源链接 `source_url`） |
| POST | `/api/admin/articles/{id}/approve` | 审核通过（仅已生成行可过审） |
| POST | `/api/admin/articles/{id}/reject` | 审核拒绝（附原因；内部触发补生成，达上限 → rejected_final） |
| POST | `/api/admin/articles/generate` | 手动补生成 `{date}`（严格零填充 ISO 校验，非法 → 400 BAD_PARAM） |

### 无鉴权

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/health` | `{status: "ok"}` |
| GET | `/admin`、`/admin/{*path}` | 管理页 SPA（静态资源回退 index.html） |

## 4. 数据模型（SQLite，10 张表）

`tool/migrations/001-init.sql`（0→1 init，开发期活版本，结构变更并入不递增版本；服务端未发布，`tool/db_version` = 0）：

- **长期实体**：`users`（phone PK，status/banned_reason/quota_word_daily）；`admin_user`（username PK，argon2 哈希）；`article`（id PK，target_date/difficulty/content_category/order_index/title/status/reject_reason/regenerate_count/prompt_tokens/completion_tokens/**source_article_id**（事实源引用，仅 NEWS 有值）；索引 `(target_date, difficulty, status)`、`(status)`）
- **关系实体**：`device_sessions`（phone + device_id，UNIQUE(phone, device_id)，issued_at/last_active_at）
- **流水账/缓存**：`usage_log`（phone 可空=任务侧，endpoint: word_lookup/article_generate，token/latency；索引 `(phone, created_at)`、`(created_at)`）；`word_lookup_cache`（word PK，result_json，created_at）
- **段落表**：`article_paragraph`（article_id FK CASCADE，order_index，text；UNIQUE(article_id, order_index)）——段落以 **`英文|||中文` 单列**存储（1NF 考量，下发时拆分，不存第二列）
- **事实源表**：`article_source`（10 列：id PK、source_url UNIQUE、title、body、published_at、is_used、created_at、updated_at、is_deleted、deleted_at；索引 `(is_used, published_at)`）——NEWS 事实锚定的抓取入库（见 §5.5）。正文入库（`body`）供生成时 prompt 注入，免生成时重抓页面（内容漂移/重抓脆弱）
- **prompt 表**：`prompt`（key PK，content，updated_at；种子即默认内容，INSERT OR IGNORE 不覆盖管理端修改）

迁移由 `db::migrate` 执行：按 `;` 切分 001-init.sql 逐条执行（全部 `IF NOT EXISTS` 幂等，空库/遗留库重复执行均安全）+ `schema_migration_log` 记一条 0→1。连接池 `max_connections = 5`、WAL、`foreign_keys = true`。

## 5. 文章管道

### 5.1 每日生成任务（tasks）

- **启动补漏**：`spawn_daily_task` 先 `run_startup_fill`——生成今天 + 明天各 15 篇（3 难度 × 5 篇；今天/明天由同一次 `Local::now()` 推导，消除跨午夜窗口非相邻日期）。失败只记日志，不阻止 serve
- **每日循环**：等待到 `DAILY_GENERATE_HOUR`（默认 3）点**整点后 1 分钟（03:01，避开整点边界）**触发，生成明天并顺带补今天（幂等、补漏成本为零）。DeepSeekClient 每轮经工厂构造（构造失败记 error + sleep 1h 重试，任务不永久停摆）；单次生成失败只记日志，循环继续
- **时区**：全部用 `Local`（服务器本地时区）——部署要求 `Asia/Shanghai`

### 5.2 预占行模式（生成，T8 审查重构）

生成 = 短事务预留 → 锁外 LLM 填充，写锁不跨 LLM 调用（LLM 单篇最长 90s，持锁会整批阻塞所有写入方）：

1. **阶段 1（BEGIN IMMEDIATE 短事务，毫秒级）**：每难度统计非终结行（pending_review/approved），缺失槽位 INSERT 预占行（title NULL、status=pending_review、regenerate_count 定值）→ COMMIT。并发 ensure 的先到者 COMMIT 后，后到者计数看到预占行即跳过——幂等成立
2. **阶段 2（无锁）**：逐行填充 `pending_review AND title IS NULL` 的预占行（LLM → 条件 UPDATE title/tokens + 段落 INSERT 短事务）；单篇失败标记 `failed`（title 仍 NULL）并继续其余行，下次 ensure 自动补预占行替换——单篇失败不回滚整批
- **每日预算**：当日（本地语义零点起）`article` 行数 ≥ `ARTICLE_BUDGET_DAILY`（默认 100）→ 400 QUOTA_EXCEEDED，防补生成循环烧钱。预占行即消耗预算（预留时校验）
- **幂等**：同一 (target_date, difficulty) 非终结行数已达 5 则跳过；已填充/已终结/不存在的行生成时幂等跳过
- **题材轮换**：难度→分类映射（LOW: DAILY_CONVERSATION/SCENE_DESCRIPTION/SIMPLE_STORY；MEDIUM: NEWS/EXPOSITORY/ARGUMENTATIVE/PERSONAL_ESSAY；HIGH: ACADEMIC_EXCERPT/DEBATE_SPEECH/LEGAL_DOCUMENT/ART_CRITICISM/CLASSIC_NOVEL_EXCERPT），以 target_date 的 epoch 天数（`num_days_from_ce`）为种子轮转，相邻两天同 order 不碰撞；补生成以 `order + regen + 1` 轮换到下一分类

### 5.3 审核状态机

```mermaid
stateDiagram-v2
    [*] --> pending_review: 每日生成/手动 generate（预占行 title NULL → LLM 填充）
    pending_review --> approved: 管理员通过（仅已生成行可过审）
    pending_review --> rejected: 管理员拒绝(附原因)
    pending_review --> failed: LLM 生成失败（title 仍 NULL，下次 ensure 补预占行替换）
    rejected --> pending_review: 自动补生成新文章(同难度, regenerate_count+1)
    rejected --> rejected_final: 补生成达上限(3次/篇)
    approved --> [*]: 目标日 0 点后对用户可见（GET /api/articles）
    rejected_final --> [*]: 不再自动补，管理员可在管理页人工处置
    failed --> pending_review: 下次 ensure 自动补预占行替换
```

- **守卫**：仅 `pending_review AND title IS NOT NULL`（已生成行）可 approve/reject——预占/生成中/失败行（title NULL）返回 404，杜绝「approved + 空标题」与误拒浪费补生成
- **并发安全**：reject 在同一短事务内完成「旧行 → rejected + 未达上限时 INSERT 补生成预占行（regenerate_count = 父行 +1）」；并发双 reject 的 UPDATE 条件不命中（affected=0）→ 不建补生成行
- **降级决策**：补生成填充失败不上抛——拒绝语义在事务内已完成，客户端重试会撞 404；新行保持 failed 由下次 ensure 自愈替换
- **审核时限**：文章前一天生成，管理员白天审核；目标日 0 点起已过审文章对用户可见，未审完的难度当天缺文章（用户读历史，不阻塞阅读）

### 5.4 下发语义

- 仅 `approved` 可见，排序 `ORDER BY difficulty, order_index`——**difficulty 为字典序**（ASCII 排序：HIGH < LOW < MEDIUM），App 端按自然难度序（LOW/MEDIUM/HIGH）自行整理
- 段落 JSON 契约：`[{order_index, english_text, chinese_translation}]` 嵌套对象（路由层组装，service 内部保持 `(order, en, zh)` 元组形态）
- 需 JWT（防匿名批量爬取）；与用户查词配额无关（文章是全局池）

### 5.5 事实源锚定（NEWS 分类）

NEWS 是事实性内容，LLM 凭空生成会幻觉虚构事件。事实锚定：NEWS 分类文章生成前先抓取 chinadaily（China Daily）真实新闻作为事实源，正文注入 prompt 并要求「基于事实重写、不得照抄、不得添加源中不存在的事实」。

弃 RSS 原因：chinadaily RSS（`/rss/*.xml`）内容停留在 2017-12 已弃用多年，只能抓 HTML。列表页链接路径自带日期（`/a/202608/17/WSxxx.html`），以此判断新鲜度窗口，无需额外日期请求。

**组件**（`src/drivers/chinadaily.rs` + `src/services/source_service.rs`）：

| 组件 | 职责 |
|---|---|
| `SourceFetcher` trait | `fetch_recent(&Config) -> Result<Vec<FetchedSource>, anyhow::Error>`——生成管线只依赖本 trait，测试注入 mock |
| `ChinadailyFetcher` | 抓 `china` + `world` 两栏目列表页 → `parse_list_links` 提取近 `SOURCE_MAX_AGE_DAYS` 天链接（URL 去重后按日期降序）→ 逐篇抓正文至多 `MAX_BODY_FETCH`(20) 篇（单篇请求/解析失败跳过，不阻断整批）。reqwest client 带 `SOURCE_FETCH_TIMEOUT_SECS` 兜底超时；构造失败由调用方降级 `NoopFetcher` |
| `NoopFetcher` | 恒返回空——构造失败降级 / 测试默认（NEWS 走自由发挥） |
| `parse_list_links` / `parse_article_page` | 纯解析函数（today/base 显式传入），fixture 可单测。文章页提取 title（去 ` - Chinadaily.com.cn` 后缀）+ `<p>` 正文纯文本（<30 字符短片段过滤；正文截断 `MAX_BODY_CHARS`=4000 控制 prompt 体积） |
| `store_sources` | 抓取产物入库：`INSERT OR IGNORE`（URL UNIQUE 幂等，重复抓取无副作用），返回新插入行数 |
| `pick_source` | 选源（见下），返回 `Option<SourceArticle>` |
| `SourceArticle` | 已选中事实源 `{id, url, title, body, published_at}`——body 供 prompt 注入 |

**管线数据流**（`ensure_daily_generation → generate_one →（NEWS）pick_source → generate_article_content → DeepSeek`）：

```mermaid
sequenceDiagram
    participant T as 每日任务 / 管理端 reject
    participant E as ensure_daily_generation
    participant G as generate_one
    participant S as source_service
    participant D as ChinadailyFetcher
    participant L as llm_service → DeepSeek

    T->>E: ensure（阶段 1 预占 → 阶段 2 填充）
    E->>G: generate_one(article_id)
    alt content_category == NEWS
        G->>S: pick_source(pool, cfg, fetcher)
        alt 池内有未用源
            S-->>G: Some(SourceArticle)（条件 UPDATE 预占）
        else 池空
            S->>D: fetch_recent（china + world 列表页 → 正文）
            S->>S: store_sources（INSERT OR IGNORE）
            S-->>G: 再 try_pick
        else 抓取失败
            S-->>G: None（warn 降级，自由发挥）
        end
    else 非 NEWS
        G-->>G: source = None
    end
    G->>L: generate_article_content(..., source)
    L->>L: 注入 {{sourceArticle}} + {{recentTitles}} 后调 DeepSeek
    L-->>G: title + paragraphs + tokens
    G->>G: 短事务：title + source_article_id + 段落
```

**选源算法（pick_source）**：单语句条件更新预占（与 §5.2 预占行模式同纪律——占用发生在 LLM 调用前，`is_used=1` 即在 LLM 调用前占用，保证并发下不重复引用同一来源）：

```mermaid
flowchart TD
    A[pick_source] --> B{try_pick<br/>SELECT 未用且未删且新鲜来源<br/>ORDER BY published_at DESC, id DESC LIMIT 1}
    B -->|命中| C{条件 UPDATE<br/>SET is_used=1 WHERE id=? AND is_used=0}
    C -->|affected = 1| D[占用成功 → Some SourceArticle]
    C -->|affected = 0<br/>并发下已被另一路占用| E{重试 < 3 次?}
    E -->|是| B
    E -->|否| F[→ None]
    B -->|池空（未补充过）| G{fetch_recent}
    G -->|成功| H[store_sources] --> B
    G -->|失败| I[warn 降级 → None<br/>NEWS 自由发挥]
```

- **新鲜度窗口**：`published_at >= 今天 - SOURCE_MAX_AGE_DAYS`（默认 3 天，只选近 N 天来源保证新鲜）
- **并发安全**：SELECT 与条件 UPDATE 分离——并发双路选中同一行时后到者 `affected=0`，重试下一行（至多 3 次），一篇来源至多被一篇生成文引用
- **池空补充**：池空先抓取再选一次；抓取失败 / 补充后仍空 → 降级 `Ok(None)`

**去重策略（三层）**：

| 层 | 机制 | 防什么 |
|---|---|---|
| 入库幂等 | `source_url` UNIQUE + `INSERT OR IGNORE` | 重复抓取不产生重复行 |
| 永久去重 | `is_used` 预占标记（条件更新原子置位） | 一篇事实源至多被一篇生成文引用，已用来源永不重选 |
| 标题防重 | `{{recentTitles}}` 注入近 `RECENT_TITLE_DAYS` 天已生成标题清单（见 §5.6） | LLM 复用相近题材/事件写同题文章 |

reject 补生成走 `generate_one` 重新选源——新预占行重新 `pick_source`（`is_used=1` 的来源不重选），补生成以 `order + regen + 1` 轮换到下一分类时自然换源，不消耗原来源。

**prompt 注入**：`article_user_prompt` 模板含 `{{sourceArticle}}` / `{{recentTitles}}` 占位符。`{{sourceArticle}}` 替换为来源块（标题/正文/日期 + 重写指令）；无源（降级 / 非 NEWS）时替换为空串——模板对全分类通用：

```
Facts source (China Daily, {published_at}):
{title}
{body}

Write an original news article based ONLY on the facts above.
Do not copy sentences from the source. Do not add facts not present in the source.
```

来源正文入库存储（`article_source.body`），生成时无需重抓页面（重抓脆弱且内容可能漂移）。

**管理端可见**：`ArticleView` 新增 `source_url: Option<String>`（`list_articles` / `get_article` / `get_approved_by_date` 三查询均 `LEFT JOIN article_source`）；admin UI 文章表格与详情抽屉显示来源链接（新窗口打开）。**T10 下发不动**：`ArticleJson` 不含 `source_url` 字段——规格「事实源不展示给用户」由不加字段保证。

**错误处理**：

| 场景 | 行为 | 结果 |
|---|---|---|
| 列表页请求失败（china/world 任一） | `fetch_recent` 整体 Err → `pick_source` warn 降级 | NEWS 自由发挥，生成不中断 |
| 抓取整链超时（60s 总预算） | `tokio::time::timeout` 触发 → warn 降级（防挂起上游卡死批处理） | NEWS 自由发挥，生成不中断 |
| 文章页请求失败 / 不可解析 | 单篇跳过（warn），继续其余 | 来源池略窄 |
| 池空（无未用源 / 全超新鲜度窗口） | 抓取补充 → 再选；仍空 → None | NEWS 自由发挥 |
| 并发选中冲突 | 条件 UPDATE affected=0 → 重试下一行（至多 3 次） | 不重复引用同一来源 |
| 生成事务写 `source_article_id` | 与 title/段落同一短事务，失败整体回滚 → 行 failed 由下次 ensure 自愈 | 无「title 非空 + 无来源」半写态 |

### 5.6 标题防重（全分类）

- **背景**：文章为全局共享池、LLM 连续多天生成易重复题材；URL/来源去重防不住「题材相同、来源不同」的撞车
- **机制**：`generate_article_content` 每次生成前查近 `RECENT_TITLE_DAYS`（默认 14）天 `title IS NOT NULL` 的文章标题（按 `target_date DESC, id DESC` 限 50 条），格式化后注入 `{{recentTitles}}` 占位符；无历史标题 → 空串（占位符替换为空）
- **prompt 指示**：清单注明「以下标题近期已发布，避免相同题材、观点或事件」（avoid the same subject, viewpoint, or event）
- **覆盖**：全分类生效（非仅 NEWS——LOW/HIGH 也防重复题材）；预占/生成中/失败行（title NULL）自动排除

## 6. 统一 envelope 与错误语义

### 6.1 envelope 格式

- 成功：HTTP 200，`{"code": 0, "data": ...}`
- 失败：`{"code": <HTTP 状态码或业务码>, "message": "...", "error_code": "<细分错误码>"}`

### 6.2 error_code 表（App 端映射回现有异常类型）

| HTTP | body `code` | `error_code` | 触发场景 | App 端行为 |
|---|---|---|---|---|
| 400 | 400 | `BAD_PARAM` | 参数错误（空 word、非法 generate 日期、登录缺 phone/deviceId） | 参数错误提示 |
| 400 | 40001 | `QUOTA_EXCEEDED` | 查词每日配额超限 / 文章日预算超限 | 提示配额 |
| 401 | 401 | `TOKEN_EXPIRED` | 未带/无效/过期 token；admin 用户名或密码错误（不区分，防枚举） | 重新登录 |
| 401 | 401 | `EVICTED` | 会话被挤掉/登出（`iat != issued_at`） | 提示已在其他设备登录 |
| 403 | 403 | `BANNED` | 账号被封禁 | 提示账号被封禁 |
| 404 | 404 | `NOT_FOUND` | 资源不存在 / 不可过审行（title NULL）/ 重复审核 | 资源不存在 |
| 500 | 500 | `LLM_FATAL` | DeepSeek 不可恢复错误 | → 现有 `LlmFatalException` |
| 500 | 500 | `PIPELINE_BLOCKING` | 管道阻塞：响应不可解析、缓存损坏、prompt 模板缺失 | → 现有异常 |
| 500 | 500 | `INTERNAL` | 未预期内部错误（记 error 日志） | 内部错误 |
| 502 | 502 | `LLM_RECOVERABLE_EXHAUSTED` | 可恢复错误重试 4 次仍失败 | → 现有 `LlmRecoverableExhaustedException` |
| 504 | 504 | `LLM_TIMEOUT` | 总预算超时 | → 现有 `LlmTimeoutException` |

### 6.3 成本控制

1. **查词缓存**：同词跨用户共享（小写 normalize），命中不调 LLM、不扣配额；TTL 30 天、上限 5000 条（超限删最旧）
2. **用户查词配额**：全局默认 200 次/天（`WORD_QUOTA_DAILY`），按用户可覆盖（admin 接口）；只计真实 LLM 调用（usage_log 计数）
3. **文章日预算**：100 篇/天（`ARTICLE_BUDGET_DAILY`）
4. **用量账本**：`usage_log` 记每次调用（查词 + 文章生成）的 token 数与延迟，管理页按单价换算成本

## 7. 时区语义（部署关键约束）

`services::today_start_millis`（今日零点毫秒）与每日任务全部基于 **`chrono::Local`（服务器本地时区）**——查词配额日界、文章日预算、用量统计、`/api/articles/today` 的"今天"均为同一口径。部署时必须 `timedatectl set-timezone Asia/Shanghai`，否则配额日界与任务触发时刻偏移。

## 8. 认证与账号体系

- **应用端**：phone = 账号，免密直登（beta 简化，预留 `code` 字段升级验证码）；`device_sessions` 为权威状态（非 JWT 黑名单）——每 phone 最多 2 个活跃会话，登录时按 `issued_at` 最旧挤掉；`issued_at` 按 phone 全局单调（MAX+1，防时钟回拨/同毫秒并发）
- **管理员**：独立 `admin_user` 表（argon2）+ 独立登录端点 → admin JWT（claim `role: admin`），`/api/admin/*` 在 extractor 层校验 role；admin token TTL **12 小时**（App token 30 天）
- **封禁**：extractor 层先查封禁再查会话——被封禁账号得 403 BANNED
