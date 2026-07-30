# 数据库创建与种子数据流程

> 用于在首次安装时植入 15 篇历史文章，让用户一打开 app 就有内容可读。

---

## 概述

整个流程分成两大阶段：

1. **数据库表创建** — Room 自动生成 `CREATE TABLE` 并执行所有 DDL
2. **种子数据写入** — `RoomDatabase.Callback.onCreate()` 在表创建完成后立即触发

```
App 启动
  │
  ├─ Room.databaseBuilder("contexta.db")
  │     ├─ .addCallback(Callback.onCreate → seedDatabase())
  │     ├─ .addMigrations(ALL = [])
  │     └─ .fallbackToDestructiveMigration()   // 仅开发期容忍 Schema 变更
  │
  └─ build() → 创建 / 打开数据库
        │
        ├─ 第一次运行 → 建表 → onCreate() → seedDatabase() 写入种子
        ├─ Schema 变更 → fallbackToDestructiveMigration() → 删库重建 → onCreate() → seedDatabase()
        └─ 正常运行 → 直接打开已有数据库，onCreate() 不执行
```

---

## 阶段一：数据库定义（`ContextaDatabase.kt`）

Room 数据库版本号为 **1**，包含 13 张表：

| 表名 | 实体类 | 用途 |
|------|--------|------|
| `user_settings` | `UserSettingsEntity` | 用户设置（难度、每日篇数等） |
| `config_change_log` | `ConfigChangeLogEntity` | 配置变更审计日志 |
| `article_batch` | `ArticleBatchEntity` | 批次（CURRENT / NEXT / EXPIRED） |
| `article` | `ArticleEntity` | 单篇文章 |
| `article_paragraph` | `ArticleParagraphEntity` | 文章段落 |
| `word` | `WordEntity` | 词汇表 |
| `word_sense` | `WordSenseEntity` | 词义 |
| `example_sentence` | `ExampleSentenceEntity` | 例句 |
| `vocabulary_entry` | `VocabularyEntryEntity` | 用户生词本 |
| `daily_learning_log` | `DailyLearningLogEntity` | 每日学习日志 |
| `learning_stats_summary` | `LearningStatsSummaryEntity` | 学习统计汇总 |
| `generation_pipeline_status` | `GenerationPipelineStatusEntity` | 生成管道状态 |
| `schema_migration_log` | `SchemaMigrationLogEntity` | Schema 迁移日志 |

**关键设计：** 目前 `Migrations.ALL = emptyArray()`（产品尚未发布），开发期间通过 `fallbackToDestructiveMigration()` 处理 Schema 变更。这意味着每次实体变更后重新安装，旧数据库会被直接删除重建。

---

## 阶段二：种子数据写入（`SeedDatabase.kt`）

### 2.1 触发时机

`AppModule.provideDatabase()` 中注册了 `RoomDatabase.Callback`：

```kotlin
.addCallback(object : RoomDatabase.Callback() {
    override fun onCreate(db: SupportSQLiteDatabase) {
        seedDatabase(context, json, db)   // ← 数据库首次创建后立即执行
    }
})
```

### 2.2 数据来源

`assets/seed_articles.json` — JSON 文件，反序列化为：

```kotlin
SeedData(
    version: Int,
    seedArticles: List<SeedArticle>
)
```

每条 `SeedArticle` 包含 `difficultyLevel`、`contentCategory`、`orderIndex`、`title`、`paragraphs`（英中对照段落列表）。

### 2.3 写入逻辑

```python
seedDate = "2026-03-29"           # 固定的"历史"日期
now = System.currentTimeMillis()  # 用于 last_updated_at / generation_completed_at

按 difficultyLevel 分组（LOW / MEDIUM / HIGH）
  └─ 每组建 1 条 article_batch 记录
       ├─ batch_type = "EXPIRED"
       ├─ status = "EXPIRED"
       ├─ difficulty_level_snapshot = difficulty
       ├─ daily_count_snapshot = 5
       ├─ generated_on = "2026-03-29"
       ├─ unlocked_on = NULL          # 从未被解锁
       └─ last_updated_at = now
       │
       └─ 该组内按 orderIndex 排序，每篇建 1 条 article 记录
            ├─ batch_id = ↑
            ├─ status = "SUCCESS"     # 直接标为完成
            ├─ retry_count = 0
            ├─ max_retries = 3
            ├─ accumulated_read_seconds = 0
            └─ generation_completed_at = now
            │
            └─ 每段建 1 条 article_paragraph 记录
                 ├─ article_id = ↑
                 ├─ order_index
                 ├─ english_text
                 └─ chinese_translation
```

### 2.4 写入结果（共 20 条记录）

| 记录类型 | 数量 |
|---------|------|
| `article_batch` | 3（LOW / MEDIUM / HIGH 各一） |
| `article` | 15（每批次 5 篇） |
| `article_paragraph` | 取决于 JSON，每篇 N 段 |

---

## 阶段三：后续批次生产线

种子数据的下一阶段由正常的生产线处理，理解它对认清种子数据的定位很重要。

### 3.1 批次的完整生命周期

```
PENDING ──claim──→ GENERATING ──全部完成──→ READY
    ↑                 │                           │
    │                 │ (若某篇 FATAL)             │
    │                 ↓                           ↓
    │              BLOCKED                    promoteToCurrent()
    ↑                                          CURRENT (unlockedOn = today)
    │                    expire()
    ├────────────────── EXPIRED (unlockedOn = null)
    │                    reactivate()
    └────────────────── NEXT
                         promoteToCurrent()
                          CURRENT (unlockedOn = today)
```

关键字段含义：
- **`generated_on`** — 批次被创建的日子（NEXT 的"出生日期"）
- **`unlocked_on`** — 批次被提升为 CURRENT 的日子（用户实际看到该批次内容的日期）。`null` 表示从未被解锁展示过

### 3.2 `article_batch` 的两个分类轴

**batch_type**（类型标签）：
- `CURRENT` — 用户今天正在看的批次
- `NEXT` — 预生成的下一批次
- `EXPIRED` — 已废弃的批次（用户已经看过的，或被难度变更废弃的）

**status**（生命周期状态）：
- `PENDING` → `GENERATING` → `READY` → `CURRENT` → `EXPIRED`

### 3.3 `unlockedOn` 是种子批次与正常批次的关键区别

- **正常批次**要经历 `PENDING → GENERATING → READY → promoteToCurrent()` 才到 `CURRENT`，`unlocked_on` 在 `promoteToCurrent()` 时设为当天日期
- **种子批次**被直接写为 `EXPIRED`，且 `unlocked_on = NULL`，跳过了整个生成管道

### 3.4 `generated_on` 与同一天同难度防重复（规则 1）

`article_batch` 表上有唯一索引：
```sql
UNIQUE(difficulty_level_snapshot, generated_on)
```

**目的：** 防止 `TriggerNextBatchUseCase` 在同一天对同一难度等级创建多个 NEXT 批次。

**与种子数据的关系：** 种子批次的日期是 `"2026-03-29"`，而 `TriggerNextBatchUseCase` 创建新批次时使用 `timeProvider.todayDateString()`（实际当天日期）。两者日期不同，所以种子批次不会触发唯一索引冲突。

---

## 阶段四：首页展示逻辑（从种子到用户看到文章）

### 4.1 启动编排（`StartupOrchestrationUseCase`）

用户首次安装后的启动流程：

```
App 启动
  │
  ├─ 1. 检查管道阻塞 → 若阻塞且版本无更新则返回 PipelineBlocked
  ├─ 2. 检查是否完成 onboarding → 未完成则返回 NeedsOnboarding
  ├─ 3. 重建卡在 GENERATING 的文章回 PENDING
  │
  ├─ 4. 检查 CURRENT 和 NEXT 批次
  │     │
  │     ├─ 无 CURRENT 且 无 NEXT → NeedsInitialBatch → CreateInitialBatchUseCase
  │     │     创建 CURRENT 批次 → 调度 Worker 生成 → 用户等待
  │     │
  │     ├─ 无 CURRENT 且 有 NEXT（且 READY）→ promoteToCurrent() + triggerNext()
  │     │
  │     ├─ 有 CURRENT 且 有 NEXT → 检查 unlocked_on 是否"隔天"
  │     │     ├─ 隔天 + NEXT 已 READY → promoteToCurrent()（来到下一批）
  │     │     └─ 隔天 + NEXT 仍在生成 → WaitingForGeneration（等待中）
  │     │
  │     └─ 没有 NEXT 或 NEXT 已 EXPIRED → triggerNext() 创建新 NEXT
  │
  └─ 最终返回 Ready → observeArticles() 展示文章
```

### 4.2 首页组装（`HomeViewModel.observeArticles()`）

```kotlin
currentBatch（可空）+ expiredBatches（列表）
  │
  ├─ CURRENT 批次 → 使用「用户当前 dailyArticleCount」做显示上限
  ├─ EXPIRED 批次 → 使用「批次自己的 dailyCountSnapshot」做显示上限
  │
  └─ 每组的 dateLabel 由 batch.unlockedOn 决定
       ├─ unlockedOn = null → dateLabel = "" → 被 .filter { it.dateLabel.isNotEmpty() } 过滤掉
       └─ unlockedOn = today → "今天"
           unlockedOn = yesterday → "昨天"
           其他 → "2026年03月29日"
```

**重要过滤器：** `第 234 行 .filter { it.dateLabel.isNotEmpty() }` 会过滤掉所有 `unlocked_on = NULL` 的批次。

这意味着种子批次只有在被提升为 CURRENT（设置了 `unlocked_on`）后才会出现在首页。

### 4.3 种子数据如何立即生效（首次启动）

修复后 `StartupOrchestrationUseCase` 的首次启动逻辑（位于 `current == null && next == null` 分支）：

```kotlin
// 优先复用已完成（种子）的 EXPIRED 批次作为初始 CURRENT，
// 让用户立即可看，无需等待 Worker 生成。
val expiredBatches = articleRepository.getExpiredBatches()
val seedBatch = expiredBatches.firstOrNull { batch ->
    batch.difficultyLevelSnapshot == settings.difficultyLevel &&
    articleRepository.isBatchComplete(batch.id)
}
if (seedBatch != null) {
    articleRepository.reactivateBatch(seedBatch.id, settings.dailyArticleCount)
    articleRepository.promoteToCurrent(seedBatch.id)
    triggerNextBatch(settings.difficultyLevel, settings.dailyArticleCount)
    return StartupResult.Ready
}
```

**完整启动流程：**

```
SeedDatabase (onCreate)
  └─ 写入 3 EXPIRED 批次（LOW / MEDIUM / HIGH），unlocked_on = NULL，文章全 SUCCESS

首次启动（onboarding 完成后）
  │
  ├─ current == null, next == null
  ├─ 查 EXPIRED 批次，发现种子数据（MEDIUM 难度，全部 SUCCESS）
  ├─ reactivateBatch() → batch_type = NEXT, status = READY
  ├─ promoteToCurrent() → batch_type = CURRENT, unlocked_on = today
  │   ╰→ 用户首页立即显示种子文章，dateLabel = "今天"
  └─ triggerNextBatch() → 创建 NEXT 批次 + 调度 Worker 后台生成
      ╰→ 第二天启动，NEXT 已 READY → promoteToCurrent()（展示新内容）
```

### 4.4 种子数据的辅助复用路径

除了首次启动直接使用外，种子批次还可以通过 `TriggerNextBatchUseCase` 的**难度变更复用逻辑**被激活：

```kotlin
// TriggerNextBatchUseCase 第 68-76 行
val reusable = expired.firstOrNull { batch ->
    batch.difficultyLevelSnapshot == difficulty &&
    articleRepository.isBatchComplete(batch.id)
}
if (reusable != null) {
    articleRepository.reactivateBatch(reusable.id, dailyCount)
    return
}
```

例如：用户切换难度回到 MEDIUM，系统从 EXPIRED 中找到种子 MEDIUM 批次（全部 SUCCESS），直接复用为 NEXT → 第二天 promoteToCurrent → 种子文章出现在首页。

---

## 数据库文件位置

真机调试时数据库文件在以下路径：

```
/data/data/com.ak.contexta/databases/contexta.db
```

可通过以下命令拉取查看：

```bash
adb exec-out run-as com.ak.contexta cat databases/contexta.db > /tmp/contexta.db
# 或
adb shell
$ run-as com.ak.contexta
$ cat databases/contexta.db > /sdcard/contexta.db
$ exit
$ adb pull /sdcard/contexta.db
```

---

## 时间线总结

| 阶段 | 发生时机 | 操作 | 影响 |
|------|---------|------|------|
| **种子的写入** | 首次安装 / 删库重装 | `onCreate` → `seedDatabase()` | 写入 3 EXPIRED 批次（15 篇文章），`unlocked_on = NULL` |
| **onboarding** | 首次使用 | App 引导用户设置难度、每日篇数 | `user_settings` 写入配置 |
| **初始启动** | onboarding 完成后启动 | 找到匹配难度的种子批次 → `reactivateBatch()` + `promoteToCurrent()`，同时 `triggerNextBatch()` 调度 Worker 后台生成 NEXT | 种子批次提升为 CURRENT，`unlocked_on = today`，用户**立即看到**文章 ✅ |
| **正常推进** | 每天打开 app | `StartupOrchestrationUseCase` → 检查 CURRENT/NEXT → 必要时 promote + triggerNext | 每天最多 5 篇文章 |
| **难度切换** | 用户修改难度 | `TriggerNextBatchUseCase` → 找可复用的 EXPIRED（含种子）→ 复用或新建 | 种子批次可能在此时"复活" |
