# Contexta Android → Flutter 迁移设计

日期：2026-08-07
状态：已确认（用户逐节审批通过）
范围：`impl/app/android`（Kotlin + Compose + Room）→ `impl/app/flutter`（Dart + Flutter + drift），功能完全一致，数据库 schema 与数据完全一致

## 背景与目标

Contexta 当前是原生 Android 实现（Compose + Room + WorkManager + 系统 TTS），处于 4 周朋友内测验证阶段。用户决定迁移到 Flutter：

1. **跨平台**：支持 iOS（KittenTTS-flutter 已支持 iOS 16+）
2. **统一技术栈**：后续迭代（含 TTS 引擎改造）在 Flutter 生态内进行
3. **功能完全一致**：以现有 main 分支（HEAD=52a162d）全部功能为基准
4. **数据库完全一致（含数据）**：schema 逐列一致，设备上已有数据直接可用

## 已确认决策（用户审批）

| # | 决策 | 内容 |
|---|---|---|
| 1 | 包名策略 | **沿用 `com.ak.contexta`**（Android applicationId 不变）+ 同一库文件 `contexta.db`，Flutter 直接打开设备上旧库 |
| 2 | 数据库方案 | **drift**（ORM），schema 用 drift Table 类逐列复刻 Room |
| 3 | 目录策略 | 新分支 `feat/flutter-migration`：新建 `impl/app/flutter`，Android 代码保留对照，**功能验证通过后删除** |
| 4 | TTS 方案 | **KittenTTS（flutter 包 `kittentts`）为默认**，系统 TTS（flutter_tts）为兜底；模型 **nano-int8 打包进 assets**（约 25MB） |
| 5 | 迁移方案 | 方案 A 完整并行迁移（后台生成、飞书告警、TTS 双引擎全部复刻） |

## 技术栈对照

| 层 | Android 原版 | Flutter 版 | 说明 |
|---|---|---|---|
| 语言/框架 | Kotlin + Jetpack Compose | Flutter (Dart ≥3.4, Flutter ≥3.22) | |
| 数据库 | Room 2.7.1（version=1, fallbackToDestructiveMigration） | **drift** schemaVersion=1 | user_version 对齐，旧库零迁移直开 |
| 状态管理 | ViewModel + StateFlow + Flow | **Riverpod** | 对应异步/流心智 |
| 网络 | Retrofit + OkHttp + 协程超时 | **dio** + Future.timeout | 拦截器/超时/取消语义对应 |
| TTS | android.speech.tts.TextToSpeech（引擎回退链） | **kittentts 包**（默认）+ **flutter_tts**（兜底） | 模型打包 assets |
| 后台 | WorkManager（expedited + 前台服务） | **flutter_workmanager** | Android 底层即 WorkManager |
| 告警签名 | javax.crypto HmacSHA256 | **crypto** 包 | |
| 种子数据 | assets/seed_articles.json | 原文件复制到 Flutter assets | 内容不变 |
| Prompt | resources/prompts/*.txt（article_system + word_lookup 2 文件） | 原文件复制到 Flutter assets | 内容不变 |
| 密钥配置 | local.properties → BuildConfig | **--dart-define-from-file** | 编译期注入等价 |
| 时间 | TimeProvider（ISO 8601 带时区偏移字符串） | DateTime + 手写格式化 | 格式必须与 Android 完全一致 |

## 数据库兼容方案（核心）

### 事实基础（探索报告）

- 库文件：`/data/data/com.ak.contexta/databases/contexta.db`，`PRAGMA user_version = 1`
- 15 张表、11 个索引（含 UNIQUE）、6 条外键（全 CASCADE）、无 DEFAULT 子句、无视图/触发器
- Room 2.7.1 默认 WAL 模式 → 磁盘上有 db + wal + shm 三件套；Room 默认 `PRAGMA foreign_keys = ON`
- `room_master_table` 与 `android_metadata` 为 Room 内部表，drift 打开时忽略即可（drift 不做 identity hash 校验，只信 user_version）
- 枚举一律 TEXT 存枚举名；Boolean 存 INTEGER 0/1；日期 `yyyy-MM-dd`、日期时间 `yyyy-MM-dd'T'HH:mm:ssXXX`（带偏移）、2 处 Unix 毫秒（INTEGER）

### 打开流程（drift MigrationStrategy）

- `beforeOpen`：`PRAGMA foreign_keys = ON`（drift 默认关闭，Room 默认开启 —— 必须显式开启保持 CASCADE 语义）
- **升级安装**（旧库存在，user_version=1 = schemaVersion）：drift 跳过一切迁移，直接读写旧数据，用户数据（生词、统计、批次、阅读记录）全部保留
- **全新安装**（无库文件）：drift `onCreate` 建表（等价 Room 首次建库）+ 写种子数据（等价 Room onCreate 回调，见下）

### 逐列复刻清单

- 类型映射：`Long/Int→INTEGER`、`Boolean→INTEGER(0/1)`、`String→TEXT`；可空列不加 NOT NULL
- 主键：`autoGenerate` → `INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL`；`learning_stats_summary.id`、`generation_pipeline_status.id` → 无自增 INTEGER PK；`daily_learning.learning_date` → TEXT 主键
- **禁止 `withDefault()`**：Room 建表无 DEFAULT 子句，默认值由应用代码填充，必须保持一致
- 索引：11 个索引命名逐一对齐（如 `index_article_batch_generated_on`、`index_word_spelling_normalized` UNIQUE）
- 外键：6 条 `ON DELETE CASCADE`（article→article_batch、article_paragraph→article、word_sense→word、example_sentence→word_sense、vocabulary_entry→word、daily_learning→article_batch）
- 15 张表名/列名：小写蛇形，逐列对齐（详细蓝图见探索报告，实现时以实体源码为准）

### 种子数据写入

- 触发：仅全新库首次创建时（等价 Room onCreate 回调），事务包裹
- 内容：3 条 article_batch（LOW/MEDIUM/HIGH，`status=READY`、`generated_on="2026-03-29"`、`last_updated_at` 按手机时区生成）+ 15 篇 SUCCESS 文章 + 105 段落
- 不写 user_settings（首次 completeOnboarding 时惰性创建 id=1）

### 数据库一致性验收（硬性步骤）

1. 用已备份的真机库（`.backup/contexta-db-2026-08-07/`）做样本：drift 打开 → `PRAGMA table_info` / `index_list` / `sqlite_master` 逐项比对 Room 蓝图
2. 真实旧库跑通全部 DAO 读操作
3. 全新安装场景：建库后逐表结构校验 + 种子条数校验（3 批次/15 文章/105 段落）
4. 备份库当前实际数据量：12 批次/60 文章/550 段落/6 天学习记录/10 单词（验收时数据量仅作 sanity check）

## TTS 方案（KittenTTS 默认 + 系统兜底）

```
speak(text, speed) → KittenTTS 已初始化 ? KittenTTS.speak() : SystemTts.speak()
启动时：尝试 KittenTTS.create()（模型从 assets 安装，失败自动回退 flutter_tts）
```

- **KittenTTS**：pub.dev `kittentts` 包（Apache 2.0，Developer preview）。本地神经网络合成，支持 Android 21+/iOS 16+，语速控制、FIFO 播放队列、8 种语音、模型选择（nano-int8 25MB 最小）
- **模型**：nano-int8 打包进 assets（约 25MB，APK/IPA 体积增加），首次启动安装到应用目录；模型文件来源沿用原 Kittentts 计划的下载来源，实现时确认
- **兜底 flutter_tts**：Android 系统 TTS（引擎回退链：小米 miBrain → Google TTS → 系统默认）+ iOS AVSpeechSynthesizer
- **行为对齐**：
  - 阅读页语速：UI 显示 1x/0.75x；系统兜底沿用 0.70f/0.45f 映射；KittenTTS 用其语速参数（实现时验证语义）
  - 全文朗读/段落朗读/单词发音/查词发音/生词自动朗读（autoPlayAudio）
  - 播放中断防串扰：原版用 utteranceId 校验迟到回调；KittenTTS 用队列 API，需要重新设计（停止当前 → 播新）
  - TTS 不可用时：用户主动点播 → Snackbar + 拉起系统 TTS 设置；自动播放静默跳过
- **不确定点（实现时验证）**：KittenTTS 播放完成回调能拿到的信息粒度；与"生词高亮/朗读中"状态结合的方式

## 后台生成方案

- **Android**：flutter_workmanager → 复刻：`enqueueUniqueWork("article_generation_batch_{id}", KEEP, ...)`、指数退避 30s、前台服务通知（渠道 `article_generation`，IMPORTANCE_LOW，"Contexta 正在生成文章"）；expedited 支持若插件不完整 → 平台通道补丁或降级普通 work（**技术风险**）
- **启动恢复**（StartupOrchestration）原样迁移：孤儿修复（GENERATING 文章/批次→PENDING）、卡死批次重调度、24h 告警补发
- **Worker 返回语义**：finished=false → retry；普通异常 attempt<2 → retry；PipelineBlocking → failure 不重试
- **iOS**：平台限制无法等价后台续跑 → 用 workmanager 的 iOS 实现（BGTaskScheduler）或前台生成 + 启动恢复兜底（原版无 iOS 版，无一致性压力）

## 领域逻辑复刻要点（探索报告 10 条关键行为）

1. `withTimeoutOrNull` + CancellationException 立即传播：超时走 LlmTimeoutException 不重试，且不取消同批次后续文章
2. Worker retry 三种触发（未完成/异常/不重试阻断）
3. 批次/文章 CAS 认领均认 GENERATING（中断恢复）；启动三重置孤儿修复
4. 每天每难度只生成一批；每批固定 5 篇；题材轮换偏移量 = `(nowMillis % 1000) % size`
5. `findNextReadyBatch` 只找 `generated_on > maxRefDate` 的批次
6. 错误落库与状态更新同事务；告警送达才回写 notified_at / ready_notified_at；补发限 24h
7. 飞书：timestamp-30s、签名 URL 编码、解析业务 code（HTTP 200 ≠ 成功）、5 分钟内存去重
8. 批次有 FATAL 文章 → 永不 READY；有未完成文章 → 不 READY 且 Worker retry
9. 前台服务通知渠道 IMPORTANCE_LOW；配额耗尽降级
10. 首页展示用 dailyCountSnapshot 历史快照；难度用当前用户难度过滤

## UI 复刻要点

- **设计系统**：颜色 token（Primary `#CC785C` 等 19 色，仅浅色模式）、字号阶梯（displayLarge 36sp serif 400 至 labelSmall 12sp，serif/sans 用系统字体族）、间距 4dp 基数、圆角（8/12/16/pill）、动效 150/200/300ms、无阴影分层、无自定义字体文件
- **7 页面**：Onboarding（3 步）、Home（日期+streak 胶囊、DayGroup 折叠、加载/生成中/空三态）、Reading（滚动进度条、分词点击正则 `[A-Za-z]+(?:['-][A-Za-z]+)*`、4 种译文模式 FULL/DIM/BLURRED/HIDDEN、blur 4dp + 10s 自动重新模糊、底部播放条、查词弹窗、120s 阅读计时、生词高亮 `0x2ECC785C`）、Vocabulary（fling 切卡 ±500px/s、FAB ✓、总结页、无 ✗ 入口）、Settings（双 tab、弹窗三件套、难度确认弹窗 + triggerNextBatch）、AddWord（四结果状态）、Reference（三 tab、26 字母 + 48 音标 + 23 语法点静态数据）
- **导航**：底部导航仅 home/reference/settings 三路由显示（vocabulary 进入后底栏消失，靠返回键退出）；startDestination=onboarding，已 onboarding 自动跳 home
- **静态数据**：alphabetData/phonicsGroups/phonemeSoundMap/grammarGroups 原样搬入 Dart

## 错误处理与监控

- AppError / DomainResult / LlmExceptions（Fatal/Timeout/RecoverableExhausted）/ PipelineBlockingException 全量迁移
- LlmErrorClassifier 三分类：Structural（含 "Constraint"/"disk I/O"）→ 阻塞管道；Fatal（400/401/403）→ 立即抛；Recoverable（网络/null/429/5xx/parse）→ 重试 3 次（429 用 Retry-After 封顶 30s，否则指数退避 2/4/8s）
- 告警类型：LLM_FATAL/STRUCTURAL（红）、文章失败（橙）、批次完成（绿）；送达标记幂等
- 密钥：`--dart-define-from-file`（DEEPSEEK_API_KEY、DEEPSEEK_BASE_URL、FEISHU_WEBHOOK_URL、FEISHU_SIGN_SECRET、LLM_TIMEOUT_MS、LLM_MAX_RETRIES 等，全部对齐原 local.properties 键）

## 测试与验收

- **单元测试**：drift 内存库测 DAO（对齐 Android test/ 目录用例，包括 Fakes）；错误分类、用例逻辑、LLM 解析（XML title/paragraph/translation）
- **数据库集成测试**：真实备份旧库打开 + 逐列比对 + 数据可读
- **真机验收**（对照探索报告行为清单 + UI 清单逐项走查）：
  1. 覆盖安装（不卸载）→ 数据完整保留
  2. KittenTTS 发音 + 系统 TTS 兜底触发
  3. 杀进程后生成续跑 + 启动孤儿修复
  4. 7 页面逐页走查

## 执行计划（10 步）

1. 创建分支（已完成 `feat/flutter-migration`）+ `flutter create`（org com.ak.contexta）+ 依赖安装
2. 数据层：drift 15 表 + 种子 + DAO（用备份真机库验证兼容）
3. 领域层：模型/用例/LLM/错误分类/prompt（Dart 单测）
4. TTS：kittentts + flutter_tts 兜底链（真机验证发音）
5. 后台生成：workmanager + 启动恢复（真机验证续跑/修复）
6. UI 设计系统：token + 12 组件
7. 7 页面逐个迁移
8. 全量验收（上节清单）
9. 删除 `impl/app/android` + 同步主题文档（ARCHITECTURE.md / UI设计系统.md / 文章生成.md / 手动录入单词.md 更新为 Flutter 实现；CLAUDE.md 仓库结构更新）
10. 提交、PR（合并回 main）

## 风险与不确定点

| 风险 | 应对 |
|---|---|
| drift 生成 SQL 与 Room 逐列差异 | 备份旧库做逐列比对测试（硬性步骤） |
| flutter_workmanager 对 expedited/前台服务支持不完整 | 平台通道补丁或降级普通 work + 启动恢复兜底 |
| KittenTTS 播放完成回调粒度/语速参数语义 | 实现时真机验证，必要时调整防串扰设计 |
| iOS 后台生成能力限制 | 降级为前台生成 + 启动恢复（平台限制，非功能缺陷） |
| 模型文件（25MB）来源与授权 | 沿用原 Kittentts 计划来源，Apache 2.0 许可 |
| 内测期间新旧版本共存（同包名） | 新分支开发期用 debug 包不影响线上；验收时覆盖安装测试 |
