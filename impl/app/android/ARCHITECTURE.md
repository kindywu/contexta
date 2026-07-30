# Contexta Android 架构实现文档

> 基于 2026-07-30 代码状态。本文档覆盖整体架构、关键模块和实现难点，帮助你理解仓库的代码。

---

## 一、整体架构概览

### 分层架构（干净架构）

```
┌──────────────────────────────────────────────────────────┐
│  ui/ — Jetpack Compose UI                               │
│  HomeScreen, ReadingScreen, SettingsScreen, ...          │
│  HomeViewModel → 调 Use Case + 观察错误 Flow             │
├──────────────────────────────────────────────────────────┤
│  worker/ — WorkManager 层（薄层胶水）                     │
│  ArticleGenerationWorker → 调 GenerateArticlesUseCase    │
├──────────────────────────────────────────────────────────┤
│  monitoring/ — 外部通知                                  │
│  FeishuAlertSender → 发送飞书机器人通知                   │
├──────────────────────────────────────────────────────────┤
│  domain/ — 纯 Kotlin，零 Android 依赖 ⭐核心层            │
│    ├── model/      领域模型                              │
│    ├── repository/ 接口定义                               │
│    ├── usecase/    业务逻辑                               │
│    ├── error/      统一错误类型                           │
│    ├── generation/ Prompt 构建                            │
│    ├── time/       时间抽象接口                           │
│    ├── tts/        TTS 引擎接口                           │
│    ├── di/         CoroutineDispatchers                   │
│    ├── LlmClient.kt LLM 客户端接口                        │
│    ├── LlmErrorClassifier.kt 错误分类器                    │
│    ├── BackgroundWorkScheduler.kt 后台调度接口              │
│    ├── DeveloperAlertSender.kt 开发者通知接口              │
│    └── AppInfoProvider.kt 应用信息接口                    │
├──────────────────────────────────────────────────────────┤
│  data/ — 数据层                                          │
│    ├── repository/ 接口实现                               │
│    ├── local/      Room 数据库 + DAO + Entity             │
│    ├── remote/     网络层（DeepSeek API）                 │
│    ├── time/       时间实现                               │
│    └── tts/        TTS 引擎实现                           │
├──────────────────────────────────────────────────────────┤
│  di/ — Hilt 依赖注入                                     │
│  AppModule, RepositoryModule, DomainModule, NetworkModule │
└──────────────────────────────────────────────────────────┘
```

### 核心原则

1. **Domain 层纯净**：`domain/` 不 import `android.*`, `data.*`, `worker.*`, `dagger.*`（仅允许 `javax.inject.*`）
2. **依赖方向朝内**：`data → domain`, `worker → domain`, `ui → domain`；domain 只依赖接口
3. **单向调用链**：`ViewModel → UseCase → Repository 接口 → RepositoryImpl → DAO/API`
4. **Worker 是薄层**：不包含业务逻辑，只负责 CAS 抢占 + 调用 UseCase + WorkManager 结果映射

---

## 二、文件目录结构（完整）

```
com.ak.contexta/
│
├── ContextaApplication.kt           ← @HiltAndroidApp
├── MainActivity.kt                  ← 入口 Activity
│
├── domain/
│   ├── model/
│   │   ├── Article.kt               ← 文章领域模型（含 error 字段）
│   │   ├── ArticleBatch.kt          ← 批次领域模型（含 error 字段）
│   │   ├── ArticleBatch.kt          ← BatchType/BatchStatus 枚举
│   │   ├── DailyStats.kt            ← 学习统计数据
│   │   ├── UserSettings.kt          ← 用户设置
│   │   ├── VocabWord.kt             ← 单词领域模型
│   │   └── WordDetail.kt            ← 单词详情
│   ├── repository/                  ← ★ 接口定义
│   │   ├── ArticleRepository.kt     ← 文章/批次仓储
│   │   ├── SettingsRepository.kt
│   │   ├── StatsRepository.kt
│   │   ├── VocabularyRepository.kt
│   │   └── WordRepository.kt
│   ├── usecase/                     ← ★ 业务逻辑集中地
│   │   ├── StartupOrchestrationUseCase.kt  ← 启动编排（批次推进 + Pipeline 恢复）
│   │   ├── CreateInitialBatchUseCase.kt    ← 首次创建批次
│   │   ├── TriggerNextBatchUseCase.kt       ← 触发下一批次生成
│   │   ├── GenerateArticlesUseCase.kt      ← LLM 生成文章
│   │   └── GetHomeArticlesUseCase.kt       ← 首页文章过滤排序
│   ├── error/                       ← ★ 统一错误处理
│   │   ├── AppError.kt             ← Recoverable / LlmFatal / Structural
│   │   ├── DomainResult.kt          ← Success<T> / Failure<T>
│   │   ├── LlmExceptions.kt        ← LlmFatalException / LlmRecoverableExhaustedException
│   │   └── PipelineBlockingException.kt
│   ├── generation/
│   │   ├── ArticlePrompts.kt       ← 文章 Prompt 模板
│   │   ├── PromptLoader.kt         ← Prompt 资源加载器
│   │   └── WordPrompts.kt          ← 单词 Prompt 模板
│   ├── time/
│   │   └── TimeProvider.kt         ← 时间抽象接口
│   ├── tts/
│   │   └── TtsEngine.kt           ← TTS 引擎接口
│   ├── di/
│   │   └── CoroutineDispatchers.kt ← Dispatcher 注入对象
│   ├── LlmClient.kt               ← LLM 调用接口
│   ├── LlmErrorClassifier.kt      ← 错误分类器（domain object）
│   ├── BackgroundWorkScheduler.kt ← 后台调度接口
│   ├── DeveloperAlertSender.kt    ← 开发者通知接口
│   └── AppInfoProvider.kt         ← 应用信息接口
│
├── data/
│   ├── repository/                  ← ★ 接口实现
│   │   ├── ArticleRepositoryImpl.kt ← 文章/批次 CRUD + promotion
│   │   ├── SettingsRepositoryImpl.kt
│   │   ├── StatsRepositoryImpl.kt
│   │   ├── VocabularyRepositoryImpl.kt
│   │   └── WordRepositoryImpl.kt
│   ├── local/
│   │   ├── ContextaDatabase.kt     ← Room DB（version 3）
│   │   ├── Converter.kt            ← TypeConverters + 日期工具
│   │   ├── Migrations.kt           ← 1→2, 2→3 迁移
│   │   ├── dao/                    ← 13 个 DAO
│   │   ├── entity/                 ← 13 个 Entity
│   │   └── seed/                   ← 种子数据（文章+单词）
│   ├── remote/
│   │   ├── DeepSeekApi.kt          ← Retrofit 接口
│   │   ├── LlmCaller.kt            ← LlmClient 实现（含重试逻辑）
│   │   └── dto/                    ← ChatRequest, ChatResponse
│   ├── time/
│   │   └── SystemTimeProvider.kt   ← TimeProvider 实现
│   ├── tts/
│   │   └── TtsEngineImpl.kt       ← TTS 引擎实现
│   └── AndroidAppInfoProvider.kt  ← AppInfoProvider 实现
│
├── monitoring/
│   └── FeishuAlertSender.kt       ← DeveloperAlertSender 实现（飞书机器人）
│
├── worker/
│   ├── ArticleGenerationWorker.kt  ← 文章生成 Worker（薄层胶水）
│   ├── GenerationScheduler.kt     ← BackgroundWorkScheduler 实现
│   ├── GenerationWorkerFactory.kt ← Hilt Worker 工厂
│   └── ArticleGenerationWorkerEntryPoint.kt ← Hilt Worker 入口
│
├── ui/
│   ├── home/
│   │   ├── HomeScreen.kt          ← 首页（轮播 + 文章列表）
│   │   └── HomeViewModel.kt       ← 首页状态管理
│   ├── reading/
│   │   ├── ReadingScreen.kt       ← 阅读页
│   │   └── ReadingViewModel.kt    ← 阅读状态管理
│   ├── vocabulary/
│   │   ├── VocabularyScreen.kt
│   │   └── VocabularyViewModel.kt
│   ├── settings/
│   │   ├── SettingsScreen.kt
│   │   └── SettingsViewModel.kt
│   ├── reference/
│   │   ├── ReferenceScreen.kt
│   │   └── ReferenceViewModel.kt
│   ├── onboarding/
│   │   ├── OnboardingScreen.kt
│   │   └── OnboardingViewModel.kt
│   ├── components/
│   │   ├── ArticleCard.kt
│   │   ├── BottomNavBar.kt
│   │   ├── EmptyState.kt
│   │   ├── LoadingIndicator.kt
│   │   └── StatCard.kt
│   └── theme/
│       ├── Color.kt
│       ├── Theme.kt
│       └── Type.kt
│
├── navigation/
│   ├── NavGraph.kt
│   └── Screen.kt
│
└── di/
    ├── AppModule.kt                 ← @Provides: Database + 13 DAO + Json
    ├── RepositoryModule.kt          ← @Binds: 5 个 Repository 接口
    ├── DomainModule.kt              ← @Binds: 6 个基础设施接口 + @Provides: CoroutineDispatchers
    └── NetworkModule.kt             ← @Provides: OkHttpClient + DeepSeekApi
```

### 测试结构

```
app/src/test/java/com/ak/contexta/
├── domain/
│   ├── error/
│   │   └── LlmErrorClassifierTest.kt       ← 错误分类逻辑测试
│   └── usecase/
│       ├── GetHomeArticlesUseCaseTest.kt   ← 文章过滤排序测试
│       ├── GenerateArticlesUseCaseTest.kt  ← 文章生成 Use Case 测试
│       └── StartupOrchestrationUseCaseTest.kt ← 启动编排测试
├── generation/
│   ├── ArticleGenerationE2eTest.kt         ← LLM 文章生成 E2E
│   └── WordGenerationE2eTest.kt            ← LLM 单词查询 E2E
├── monitoring/
│   └── FeishuAlertSenderTest.kt            ← 飞书通知测试（JSON + 签名）
└── testing/
    └── LlmTestClient.kt                    ← 测试用 LLM 客户端
```

---

## 三、核心业务流程（重点/难点）

### 3.1 批次生命周期（Batch Lifecycle）

这是整个应用的核心状态机，理解这个才能真正理解代码。

```
PENDING ──→ GENERATING ──→ READY ──→ CURRENT ──→ EXPIRED
                │                            │
                ├──→ FAILED (重试耗尽)         └──→ BLOCKED (代码bug)
                └──→ FATAL (LLM 认证错误)
```

**批次类型（batch_type）**：
- `CURRENT` — 当前正在展示的批次（用户看到的就是这个）
- `NEXT` — 预生成的下一批
- `EXPIRED` — 已过期的批次（昨天的文章）

**状态流转详解**：

```
createBatch() → batch_type='CURRENT', status='PENDING'
    │
    ▼
claimBatch() → status='GENERATING' (CAS 操作，只有 PENDING 才能抢占)
    │
    ▼
文章逐篇生成 (GenerateArticlesUseCase)
    │
    ├── 全部生成成功 → markBatchReady() → status='READY'
    │
    ├── 有 FATAL 文章 → 保持 GENERATING（等待用户手动重试）
    │
    └── 有 BLOCKED 错误 → markBatchBlocked() → status='BLOCKED'
    │
    ▼
第二天启动时 (StartupOrchestrationUseCase):
    isNextDay(unlockedOn, today) == true
        → promoteNextToCurrent() → 旧 batch 变 EXPIRED
                                 → 新 batch 变 CURRENT (unlocked_on=today)
```

**关键代码位置**：
- `StartupOrchestrationUseCase.kt` — 启动时判断「是否新的一天」并推进批次
- `ArticleRepositoryImpl.promoteNextToCurrent()` — 批次推进逻辑
- `ArticleBatchDao` — CAS 抢占 + 状态更新 SQL

**难点 ⚡：首页显示多个日期分组**

之前 bug 是只加载了 CURRENT batch。修复后：

```kotlin
// HomeViewModel.kt — observeArticles()
val currentBatch = articleRepository.getCurrentBatch()  // batch_type='CURRENT'
val expiredBatches = articleRepository.getExpiredBatches()  // batch_type='EXPIRED'

// 每个批次生成独立 Flow，用 combine 合并
combine(allFlows) { results ->
    results.map { (batch, articles) ->
        ArticleGroupUi(
            dateLabel = dateLabelFor(batch.unlockedOn),  // "今天"/"昨天"/"2026年7月29日"
            articles = filteredArticles
        )
    }
}
```

`dateLabelFor()` 逻辑：
- `unlockedOn == today` → "今天"
- `unlockedOn == yesterday` → "昨天"
- 其他 → "2026年7月29日"（年月日完整格式）

DAO 层面需使用 `observeAllByType("EXPIRED")` 获取所有过期批次（而非 `LIMIT 1`）。

---

### 3.2 文章生成流程（重点）

```
用户打开App
    │
    ▼
StartupOrchestrationUseCase.onAppStart()
    │
    ├── 首次使用 → NeedsInitialBatch → createInitialBatch()
    │                                       │
    │                                       ▼
    │                               GenerationScheduler.scheduleBatchGeneration()
    │                                       │
    │                                       ▼
    │                               ArticleGenerationWorker.doWork()
    │                                       │
    │                                       ├── claimBatch() // CAS 抢占
    │                                       │
    │                                       ▼
    │                               GenerateArticlesUseCase.invoke()
    │                                       │
    │                                       ▼
    │                               对每个 PENDING 文章:
    │                               ├── claimArticle() // CAS 抢占
    │                               ├── LlmClient.call(systemPrompt, userPrompt)
    │                               ├── parseArticleLlmResponse()
    │                               └── completeArticle()
    │
    ├── 第二天 → isNextDay(unlockedOn, today)
    │               ├── promoteNextToCurrent() // 推进批次
    │               └── triggerNextBatch()     // 创建新 NEXT 批次
    │
    └── 正常 → observeCurrentBatch()（现为 observeArticles()）
```

**难点 ⚡：Worker 中的 CAS 抢占**

```kotlin
// ArticleGenerationWorker.doWork()
if (!articleRepository.claimBatch(batchId)) {
    return Result.success()  // 别人已经抢占了，直接成功退出
}

// GenerateArticlesUseCase 内
for (article in articles) {
    if (article.status.name == "SUCCESS") continue  // 跳过已生成的
    if (!articleRepository.claimArticle(article.id)) continue  // CAS 抢占
    // ... 调用 LLM 生成
}
```

CAS 的 SQL 实现：只有 `status='PENDING'` 的文章才能被抢走，确保 Worker 重试不重复生成。

**Prompt 模板机制**：

```kotlin
// domain/generation/ArticlePrompts.kt
fun buildArticleSystemPrompt(difficulty: String): String  // 根据难度返回系统提示词
fun buildArticleUserPrompt(category: String, orderIndex: Int): String  // 文章内容提示
fun parseArticleLlmResponse(content: String): Pair<String, List<ArticleParagraph>>  // 解析 LLM 返回的 JSON
```

Prompt 模板存放在 `assets/` 目录（通过 `PromptLoader` 加载）。

---

### 3.3 错误处理体系（重点/难点）

这是重构后的核心模块，三分类错误处理：

```
AppError
├── Recoverable      → 网络超时、429 限流、5xx、JSON 解析失败
│                      → 自动重试（指数退避），耗尽后写 DB + 用户手动重试
│
├── LlmFatal         → 401/403 认证、400 请求格式、内容策略拒绝
│                      → 直接写 DB（FATAL），不自动重试
│                      → ★ 飞书通知开发者（同 errorCode + batchId 5分钟去重）
│
└── Structural       → DB 约束冲突、序列化异常、代码逻辑错误
                      → 阻塞整个 pipeline（BLOCKED）
                      → ★ 飞书通知开发者（代码 bug）
```

**错误分类器**：`domain/LlmErrorClassifier.kt`（domain object，无 Android 依赖）

```kotlin
fun classify(httpCode: Int?, throwable: Throwable): LlmError {
    // 先判断结构性错误（PipelineBlockingException）
    // 再判断可恢复错误（429, 5xx, JSON 解析）
    // 再判断 LLM 致命错误（400, 401, 403）
    // 其余默认 Recoverable
}
```

**Use Case 内错误处理**（`GenerateArticlesUseCase.kt`）：

```kotlin
try {
    // LLM 调用 + 解析
} catch (e: LlmFatalException) {
    articleRepository.fatalArticle(article.id)   // 写 DB → FATAL
    continue                                      // 跳过这篇，继续下一篇
} catch (e: LlmRecoverableExhaustedException) {
    articleRepository.failArticle(article.id, "FAILED")
    continue
} catch (e: PipelineBlockingException) {
    articleRepository.fatalArticle(article.id)
    articleRepository.markBatchBlocked(batchId, ...)
    throw e  // 往外抛，Worker 捕获后返回 Result.failure()
} catch (e: Exception) {
    articleRepository.failArticle(article.id, "TIMEOUT")
    continue
}
```

**飞书通知**（`monitoring/FeishuAlertSender.kt`）：
- 使用 HMAC-SHA256 签名校验（`timestamp + "\n" + secret` 作为密钥）
- 5 分钟去重（`errorCode + batchId` 组合）
- `BuildConfig.DEBUG` 时自动跳过

---

### 3.4 首页文章列表分组逻辑

**数据流**：

```
HomeViewModel.loadHome()
    │
    ├── 计算日期标签（2026年7月30日 星期四）
    ├── 获取连续天数
    ├── StartupOrchestrationUseCase → 确定启动状态
    │
    └── observeArticles() ← 核心方法
            │
            ├── getCurrentBatch()  → batch_type='CURRENT'
            ├── getExpiredBatches() → batch_type='EXPIRED'
            │
            ├── 为每个批次创建 Flow<Articles>
            │   └── combine(flows) → 合并为一个 Flow<List<ArticleGroupUi>>
            │
            └── collect → 更新 UI 状态
```

**ArticleGroupUi 结构**：

```kotlin
data class ArticleGroupUi(
    val dateLabel: String,      // "今天" | "昨天" | "2026年7月29日"
    val articles: List<ArticleItemUi>
)
```

**每个 group 的应用逻辑**：
- 过滤：排除 `PENDING` 文章
- 难度匹配：`categoryToDifficulty(contentCategory) == userDifficulty`
- 排序：按 `orderIndex` 升序
- 数量限制：`dailyCountSnapshot`

**UI 渲染**（`HomeScreen.kt`）：

```kotlin
LazyColumn {
    item { HomeHeader(greeting, dateLabel, streak) }
    
    state.articleGroups.forEach { group ->
        item { DayGroup(dateLabel, articles, onArticleClick) }
    }
}
```

`DayGroup` 支持展开/折叠（`AnimatedVisibility`），点击日期行切换。

---

### 3.5 DI 模块结构（完整）

| DI 模块 | 类型 | 绑定内容 |
|---------|------|---------|
| `AppModule.kt` | `@Provides` | `ContextaDatabase` + 13 个 DAO + `Json` |
| `RepositoryModule.kt` | `@Binds` | 5 个 Repository 接口→实现 |
| `DomainModule.kt` | `@Binds` + `@Provides` | 6 个基础设施接口（TimeProvider, LlmClient, TtsEngine, BackgroundWorkScheduler, DeveloperAlertSender, AppInfoProvider）+ `CoroutineDispatchers` |
| `NetworkModule.kt` | `@Provides` | `OkHttpClient` + `DeepSeekApi` |

**为什么 DAO 用 @Provides 而不是 @Binds**：
因为 Room 的 DAO 方法是抽象方法，Dagger/Hilt 无法自动推断如何实例化它们，需要通过 `db.xxxDao()` 工厂方法显式提供。

---

### 3.6 数据库设计

- **版本**：3（通过 Migration 1→2→3 升级）
- **Migration 1→2**：给 `article` 表加 error 字段（`error_code`, `error_message`, `error_help`, `max_retries`, `next_retry_at`）
- **Migration 2→3**：给 `article_batch` 表加 error 字段（`error_code`, `error_message`, `blocked_reason`, `blocked_at`）
- **`fallbackToDestructiveMigration()`**：开发期间开启，生产环境需移除

**关键 Entity**：

| Entity | 表名 | 关键字段 | 关系 |
|--------|------|---------|------|
| `ArticleBatchEntity` | `article_batch` | `batch_type`, `status`, `generated_on`, `unlocked_on`, `blocked_reason` | 1→N Article |
| `ArticleEntity` | `article` | `batch_id`(FK), `title`, `status`, `content_category`, `error_code` | N→1 ArticleBatch |
| `ArticleParagraphEntity` | `article_paragraph` | `article_id`(FK), `order_index`, `english_text`, `chinese_translation` | N→1 Article |
| `UserSettingsEntity` | `user_settings` | `difficulty_level`, `daily_article_count`, `translation_display_mode` | 单例 |
| `GenerationPipelineStatusEntity` | `generation_pipeline_status` | `is_blocked`, `blocked_reason`, `blocked_at`, `blocked_app_version_code` | 单例 |

---

## 四、关键设计决策（TADs）

### 4.1 为什么 TimeProvider 要作为接口注入？

避免 `System.currentTimeMillis()` 在测试中无法控制。通过 `TimeProvider` 接口 + `FakeTimeProvider`，测试可以固定时间断言。

### 4.2 为什么 Worker 用 CAS claim 而不是直接更新状态？

Worker 可能被 WorkManager 重试（系统 kill、crash），CAS 确保：
- 只有 `PENDING` 状态的 batch/article 才能被抢占
- 已生成的文章（`SUCCESS`）不会被重复处理
- 多 Worker 不会冲突

### 4.3 为什么飞书通知要放 monitoring 包？

`monitoring/` 是一个独立的概念层——它不属于 data（不是业务数据存储），不属于 domain（不是核心逻辑），是一个横切关注点。独立包使其可以单独测试、单独替换（例如换成钉钉通知）。

### 4.4 为什么首页要支持多个日期分组？

用户每天会收到一个新的文章批次。第二天旧批次变为 `EXPIRED`，但用户可能还没读完。所以首页同时展示"今天"和"昨天"甚至更早的文章，方便用户回溯。

---

## 五、配置与构建

- **Min SDK**：26
- **依赖注入**：Hilt
- **数据库**：Room
- **网络**：Retrofit + OkHttp + kotlinx.serialization
- **UI**：Jetpack Compose
- **后台任务**：WorkManager
- **TTS**：Android TextToSpeech
- **时区**：硬编码 `Asia/Shanghai`
- **LLM**：DeepSeek API（通过 `LlmCaller` 封装，支持重试）

### 关键 Gradle 配置

```kotlin
// app/build.gradle.kts — BuildConfig 字段
buildConfigField("String", "FEISHU_WEBHOOK_URL", "\"https://open.feishu.cn/open-apis/bot/v2/hook/...\"")
buildConfigField("String", "FEISHU_SIGN_SECRET", "\"...\"")
```

---

## 六、测试策略

| 类型 | 框架 | 覆盖范围 |
|------|------|---------|
| 单元测试 | JUnit5 + MockK | Use Case 逻辑、Error Classifier、FeishuAlertSender |
| E2E 测试 | JUnit5 | LLM 文章生成（调真实 API）、单词查询 |
| 集成测试 | 待补充 | Room DAO、Repository 实现 |

**Mock 策略**：
- Use Case 测试使用 `mockk`（`relaxed = true` 自动返回默认值）
- 时间相关用 `FakeTimeProvider`
- LLM 相关用 `LlmTestClient`（返回预定义内容）

---

## 七、常见问题与排查

### Q: 文章列表没有按日期分组
看数据库 `article_batch` 表的 `batch_type` 字段是否正确：
```sql
SELECT id, batch_type, status, unlocked_on FROM article_batch;
```
预期结果：
```
1|EXPIRED|EXPIRED|2026-07-29    ← 昨天的批次
2|NEXT|INVALIDATED|             ← 无效化批次（可忽略）
3|CURRENT|CURRENT|2026-07-30   ← 今天的批次
```

如果 `batch_type` 不对（如旧 bug 导致 batch_type 没更新），需要手动修复：
```sql
UPDATE article_batch SET batch_type = 'EXPIRED' WHERE id = 1;
UPDATE article_batch SET batch_type = 'CURRENT' WHERE id = 3;
```

### Q: Worker 生成了文章但 UI 没看到
1. 检查文章 status 是否为 `SUCCESS`
2. 检查 `categoryToDifficulty(contentCategory)` 是否匹配用户难度
3. 检查 `daily_count_snapshot` 是否足够大

### Q: 飞书通知没收到
1. `BuildConfig.DEBUG` 为 true 时跳过通知
2. 同 errorCode + batchId 5 分钟内不重复
3. 检查 Webhook URL 和签名密钥是否配置正确
