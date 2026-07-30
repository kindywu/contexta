# Contexta Android 架构文档

> 基于 2026-07-30 代码状态。本文档为总索引，概述整体架构、目录结构和设计原则。各业务模块的详细文档见对应子文档。

---

## 一、整体架构概览

### 分层架构（干净架构）

```
┌──────────────────────────────────────────────────────────┐
│  ui/ — Jetpack Compose UI                               │
│  onboarding / home / reading / vocabulary / reference / settings │
│  每个 Screen 对应一个 ViewModel，ViewModel 调 Use Case    │
├──────────────────────────────────────────────────────────┤
│  worker/ — WorkManager 层（薄层胶水）                     │
│  ArticleGenerationWorker → 调 GenerateArticlesUseCase    │
├──────────────────────────────────────────────────────────┤
│  monitoring/ — 外部通知                                  │
│  FeishuAlertSender → 发送飞书机器人通知                   │
├──────────────────────────────────────────────────────────┤
│  domain/ — 纯 Kotlin，零 Android 依赖 ⭐核心层            │
│    ├── model/      领域模型                               │
│    ├── repository/ 接口定义                               │
│    ├── usecase/    业务逻辑                               │
│    ├── error/      统一错误类型                           │
│    ├── generation/ Prompt 构建                            │
│    ├── time/       时间抽象接口                           │
│    ├── tts/        TTS 引擎接口                           │
│    ├── di/         CoroutineDispatchers                   │
│    ├── LlmClient.kt        LLM 客户端接口                 │
│    ├── LlmErrorClassifier.kt  错误分类器                   │
│    ├── BackgroundWorkScheduler.kt  后台调度接口             │
│    ├── DeveloperAlertSender.kt    开发者通知接口            │
│    └── AppInfoProvider.kt        应用信息接口              │
├──────────────────────────────────────────────────────────┤
│  data/ — 数据层                                          │
│    ├── repository/ 接口实现                               │
│    ├── local/      Room 数据库 + DAO + Entity + Seed      │
│    ├── remote/     网络层（DeepSeek API）                 │
│    ├── time/       时间实现                               │
│    └── tts/        TTS 引擎实现                           │
├──────────────────────────────────────────────────────────┤
│  di/ — Hilt 依赖注入                                     │
│  AppModule / RepositoryModule / DomainModule / NetworkModule│
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
│   │   ├── Article.kt               ← 文章领域模型
│   │   ├── ArticleBatch.kt          ← 批次（BatchStatus 枚举）
│   │   ├── DailyLearningInfo.kt     ← 每日学习记录+关联批次
│   │   ├── DailyStats.kt            ← 学习统计
│   │   ├── UserSettings.kt          ← 用户设置
│   │   ├── VocabWord.kt             ← 生词（VocabStatus 枚举）
│   │   └── WordDetail.kt            ← 单词详情（含释义+例句）
│   ├── repository/                  ← ★ 接口定义
│   │   ├── ArticleRepository.kt     ← 文章/批次/每日分配
│   │   ├── SettingsRepository.kt    ← 用户设置
│   │   ├── StatsRepository.kt       ← 学习统计
│   │   ├── VocabularyRepository.kt  ← 生词本
│   │   └── WordRepository.kt        ← 单词查询
│   ├── usecase/                     ← ★ 业务逻辑
│   │   ├── StartupOrchestrationUseCase.kt  ← 启动编排
│   │   ├── ActivateSeedBatchUseCase.kt     ← 激活种子批次
│   │   ├── CreateInitialBatchUseCase.kt    ← 创建初始批次
│   │   ├── TriggerNextBatchUseCase.kt      ← 触发下一批次
│   │   ├── GenerateArticlesUseCase.kt      ← LLM 生成文章
│   │   └── GetHomeArticlesUseCase.kt       ← 首页文章过滤排序
│   ├── error/                       ← ★ 统一错误处理
│   │   ├── AppError.kt              ← Recoverable / LlmFatal / Structural
│   │   ├── DomainResult.kt          ← Success<T> / Failure<T>
│   │   ├── LlmExceptions.kt         ← LlmFatalException / LlmRecoverableExhaustedException
│   │   └── PipelineBlockingException.kt
│   ├── generation/
│   │   ├── ArticlePrompts.kt        ← 文章 Prompt 构建+解析
│   │   ├── WordPrompts.kt           ← 单词 Prompt 构建+解析
│   │   └── PromptLoader.kt          ← 资源文件 Prompt 加载器
│   ├── time/  TimeProvider.kt       ← 时间抽象接口
│   ├── tts/   TtsEngine.kt          ← TTS 引擎接口
│   ├── di/    CoroutineDispatchers.kt
│   ├── LlmClient.kt                 ← LLM 调用接口
│   ├── LlmErrorClassifier.kt        ← 错误分类器
│   ├── BackgroundWorkScheduler.kt   ← 后台调度接口
│   ├── DeveloperAlertSender.kt      ← 开发者通知接口
│   └── AppInfoProvider.kt           ← 应用信息接口
│
├── data/
│   ├── repository/
│   │   ├── ArticleRepositoryImpl.kt ← 文章/批次/每日分配实现
│   │   ├── SettingsRepositoryImpl.kt
│   │   ├── StatsRepositoryImpl.kt   ← 统计计算+连续天数
│   │   ├── VocabularyRepositoryImpl.kt
│   │   └── WordRepositoryImpl.kt    ← 3-tier 查词+LRU 缓存
│   ├── local/
│   │   ├── ContextaDatabase.kt      ← Room DB（version 1）
│   │   ├── Converter.kt             ← TypeConverters + 日期工具
│   │   ├── Migrations.kt            ← Migration 数组（当前为空）
│   │   ├── dao/                     ← 14 个 DAO
│   │   ├── entity/                  ← 14 个 Entity
│   │   └── seed/
│   │       ├── SeedArticle.kt       ← 种子文章数据模型
│   │       └── SeedDatabase.kt      ← 首次安装写入种子数据
│   ├── remote/
│   │   ├── DeepSeekApi.kt           ← Retrofit 接口
│   │   ├── LlmCaller.kt             ← LlmClient 实现（含重试逻辑）
│   │   └── dto/                     ← ChatRequest, ChatResponse
│   ├── time/  SystemTimeProvider.kt
│   ├── tts/   TtsEngineImpl.kt      ← TTS 实现（引擎回退链）
│   └── AndroidAppInfoProvider.kt
│
├── monitoring/
│   └── FeishuAlertSender.kt         ← DeveloperAlertSender 实现
│
├── worker/
│   ├── ArticleGenerationWorker.kt   ← 文章生成 Worker
│   ├── GenerationScheduler.kt       ← BackgroundWorkScheduler 实现
│   ├── GenerationWorkerFactory.kt   ← Hilt Worker 工厂
│   └── ArticleGenerationWorkerEntryPoint.kt
│
├── ui/
│   ├── onboarding/
│   │   ├── OnboardingScreen.kt      ← 3 步引导
│   │   └── OnboardingViewModel.kt
│   ├── home/
│   │   ├── HomeScreen.kt            ← 首页（多日期分组）
│   │   └── HomeViewModel.kt         ← 启动编排+文章观察
│   ├── reading/
│   │   ├── ReadingScreen.kt         ← 阅读页（单词点击+TTS）
│   │   └── ReadingViewModel.kt      ← 自动已读计时+查词
│   ├── vocabulary/
│   │   ├── VocabularyScreen.kt      ← 生词卡片复习
│   │   └── VocabularyViewModel.kt
│   ├── reference/
│   │   ├── ReferenceScreen.kt       ← 参考页（TTS）
│   │   └── ReferenceViewModel.kt
│   ├── settings/
│   │   ├── SettingsScreen.kt        ← 设置页
│   │   └── SettingsViewModel.kt     ← 难度/篇数/翻译/阈值
│   ├── components/
│   │   ├── ArticleCard.kt           ← 文章卡片
│   │   ├── BottomNavBar.kt          ← 底部导航
│   │   ├── LoadingIndicator.kt      ← 加载指示器
│   │   └── StatCard.kt              ← 统计卡片
│   └── theme/
│       ├── Color.kt
│       ├── Theme.kt
│       └── Type.kt
│
├── navigation/
│   ├── NavGraph.kt                  ← 导航图
│   └── Screen.kt                    ← 路由定义
│
└── di/
    ├── AppModule.kt                 ← @Provides: DB + 14 DAO
    ├── RepositoryModule.kt          ← @Binds: 5 个 Repository
    ├── DomainModule.kt              ← @Binds: 6 个基础设施接口
    └── NetworkModule.kt             ← @Provides: OkHttp + DeepSeekApi
```

---

## 三、路由与页面

| 路由 | Screen | ViewModel | 说明 |
|------|--------|-----------|------|
| `onboarding` | OnboardingScreen | OnboardingViewModel | 首次使用引导：选择水平→篇数→确认 |
| `home` | HomeScreen | HomeViewModel | 首页：多日期分组文章列表 |
| `reading/{articleId}` | ReadingScreen | ReadingViewModel | 阅读页：翻译模式/查词/TTS/自动已读 |
| `vocabulary` | VocabularyScreen | VocabularyViewModel | 生词本：卡片复习流 |
| `reference` | ReferenceScreen | ReferenceViewModel | 参考页 |
| `settings` | SettingsScreen | SettingsViewModel | 设置页：难度/篇数/翻译/阈值/TTS |

---

## 四、DI 模块结构

| 模块 | 类型 | 绑定内容 |
|------|------|---------|
| `AppModule.kt` | `@Provides` | `ContextaDatabase` + 14 个 DAO |
| `RepositoryModule.kt` | `@Binds` | 5 个 Repository 接口→实现 |
| `DomainModule.kt` | `@Binds` + `@Provides` | 6 个基础设施接口（TimeProvider, LlmClient, TtsEngine, BackgroundWorkScheduler, DeveloperAlertSender, AppInfoProvider）+ `CoroutineDispatchers` |
| `NetworkModule.kt` | `@Provides` | `OkHttpClient` + `DeepSeekApi` |

> 为什么 DAO 用 `@Provides` 而不是 `@Binds`：Room 的 DAO 是抽象方法，Dagger/Hilt 无法自动推断实例化方式，需通过 `db.xxxDao()` 工厂方法显式提供。

---

## 五、配置与构建

- **Min SDK**：26
- **依赖注入**：Hilt
- **数据库**：Room（version 1，`fallbackToDestructiveMigration`）
- **网络**：Retrofit + OkHttp + kotlinx.serialization
- **UI**：Jetpack Compose
- **后台任务**：WorkManager（指数退避 30s，KEEP 策略防重复）
- **TTS**：Android TextToSpeech（引擎回退链：小米 → Google → 系统默认）
- **时区**：硬编码 `Asia/Shanghai`
- **LLM**：DeepSeek API（`LlmCaller` 封装，最多 3 次重试，120s 超时）

### 关键 Gradle 配置

```kotlin
buildConfigField("String", "FEISHU_WEBHOOK_URL", "\"...\"")
buildConfigField("String", "FEISHU_SIGN_SECRET", "\"...\"")
buildConfigField("String", "DEEPSEEK_MODEL", "\"...\"")
```

---

## 六、文档索引

以下文档按用户功能视角组织，覆盖全部 6 个路由页面和相关技术基础设施：

| # | 文档 | 对应路由 | 说明 |
|---|------|---------|------|
| 1 | [数据库初始化.md](数据库初始化.md) | — | Entity 表结构、种子数据、TypeConverters、数据库版本 |
| 2 | [TTS朗读.md](TTS朗读.md) | — | TTS 引擎接口、实现、引擎回退链、语速切换 |
| 3 | [文章生成.md](文章生成.md) | — | 批次状态机、CAS 抢占、每日分配、Worker 后台生成、LLM 调用与重试 |
| 4 | [阅读文章.md](阅读文章.md) | `reading/{articleId}` | 阅读页交互、2min 自动已读、翻译三模式、段落揭示 |
| 5 | [查词.md](查词.md) | `reading`(内嵌) / `reference` | 3-tier 查词流程、LRU 缓存、拼写归一化 |
| 6 | [生词本.md](生词本.md) | `vocabulary` | 卡片复习流、掌握阈值、连续正确递增、软删除 |
| 7 | [首页.md](首页.md) | `home` | 多日期分组、文章过滤排序、展开/折叠、连续天数徽章 |
| 8 | [引导与设置.md](引导与设置.md) | `onboarding` / `settings` | 3 步引导、难度/篇数/翻译模式/掌握阈值/TTS/自动朗读设置 |
| 9 | [学习统计.md](学习统计.md) | — | 每日学习日志、统计表单例、连续天数算法 |
| 10 | [错误监控.md](错误监控.md) | — | 三分类错误体系、飞书通知、Pipeline 阻塞恢复 |

---

## 七、测试结构

```
app/src/test/java/com/ak/contexta/
├── domain/
│   ├── error/
│   │   └── LlmErrorClassifierTest.kt
│   └── usecase/
│       ├── GetHomeArticlesUseCaseTest.kt
│       ├── GenerateArticlesUseCaseTest.kt
│       └── StartupOrchestrationUseCaseTest.kt
├── generation/
│   ├── ArticleGenerationE2eTest.kt
│   └── WordGenerationE2eTest.kt
├── monitoring/
│   └── FeishuAlertSenderTest.kt
└── testing/
    └── LlmTestClient.kt
```

| 类型 | 框架 | 覆盖范围 |
|------|------|---------|
| 单元测试 | JUnit5 + MockK | Use Case 逻辑、Error Classifier、FeishuAlertSender |
| E2E 测试 | JUnit5 | LLM 文章生成（真实 API）、单词查询 |

### Mock 策略

- Use Case 测试使用 `mockk`（`relaxed = true` 自动返回默认值）
- 时间相关用 `FakeTimeProvider`
- LLM 相关用 `LlmTestClient`（返回预定义内容）
