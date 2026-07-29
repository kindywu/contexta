# 种子数据 + DeepSeek 授权 + Worker 日志设计

## 概述

解决三个问题：
1. 新用户完成向导后文章列表为空 → 用种子文章预填数据库，立即可读
2. 后台生成文章需要用户授权 DeepSeek API 使用 → 启动时弹框确认
3. 后台 Worker 执行缺乏可见性 → 增加关键路径日志

## 1. 种子数据

### 数据来源

15 篇英文文章人工编写（参考 `article_system.txt` 格式要求），按等级分配：

| 等级 | 篇数 | 单词量 | 类别分配 |
|------|------|--------|----------|
| LOW  | 5    | 50-100 | DAILY_CONVERSATION(2) / SCENE_DESCRIPTION(2) / SIMPLE_STORY(1) |
| MEDIUM | 5  | 100-300 | NEWS(2) / EXPOSITORY(1) / ARGUMENTATIVE(1) / PERSONAL_ESSAY(1) |
| HIGH | 5    | 300-600 | ACADEMIC_EXCERPT(1) / DEBATE_SPEECH(1) / LEGAL_DOCUMENT(1) / ART_CRITICISM(1) / CLASSIC_NOVEL_EXCERPT(1) |

### 存储格式

`app/src/main/assets/seed_articles.json`

```json
{
  "version": 1,
  "seedArticles": [
    {
      "difficultyLevel": "LOW",
      "contentCategory": "DAILY_CONVERSATION",
      "orderIndex": 1,
      "title": "...",
      "paragraphs": [
        {
          "orderIndex": 1,
          "englishText": "...",
          "chineseTranslation": "..."
        }
      ]
    }
  ]
}
```

### 加载时机：Room `Callback.onCreate()`

在 `AppModule.provideDatabase()` 中注册 `RoomDatabase.Callback`：

```kotlin
@Provides @Singleton
fun provideDatabase(@ApplicationContext context: Context, json: Json): ContextaDatabase {
    return Room.databaseBuilder<ContextaDatabase>(context, ContextaDatabase::class.java, "contexta.db")
        .addCallback(object : Callback() {
            override fun onCreate(db: SupportSQLiteDatabase) {
                // DB 首次创建 → 写入种子数据
                seedDatabase(context, json, db)
            }
        })
        .addMigrations(*Migrations.ALL)
        .fallbackToDestructiveMigration()
        .build()
}
```

**特征**：
- `Callback.onCreate()` 仅在新创建 SQLite 文件时触发一次。后续启动 DB 已存在，不运行
- 使用 `SupportSQLiteDatabase` + `ContentValues` 写入（DAO 不可用，因为 DB 尚未构建完成）
- 若回调失败，Room 抛出异常，App crash — 没有兜底，因为"重试也不可能成功"

### 种子批次结构

单个种子 batch 包含全部 15 篇文章（混合 3 个等级）：

| 字段 | 值 |
|------|----|
| batch_type | `CURRENT` |
| status | `CURRENT` |
| difficulty_level_snapshot | `"SEED"` |
| daily_count_snapshot | 5 |
| generated_on | 设备当前日期 |
| unlocked_on | 设备当前日期 |

### 等级过滤 & 每日篇数截断

`HomeViewModel.observeCurrentBatch()` 中：

```kotlin
// 按用户等级过滤文章
val filtered = articles
    .filter { it.status != ArticleStatus.PENDING }
    .filter { categoryToDifficulty(it.contentCategory) == userDifficulty }
    .sortedBy { it.orderIndex }
    .take(dailyCount)
```

用户选择 MEDIUM / 每日 3 篇：
1. 从 15 篇种子中筛选 `contentCategory → MEDIUM` 的 5 篇
2. 按 `orderIndex` 排序
3. `take(3)` 取前 3 篇

正常批次（单等级）不受影响：所有文章 `categoryToDifficulty == userDifficulty`，filter 通过全部。

### `categoryToDifficulty()` 映射复用

`ArticlePrompts.kt` 已有 `categoryToDifficulty()` 函数（`data/remote` → `domain/generation`），在 `HomeViewModel` 中直接复用。

### 生命周期

种子批次是普通 CURRENT batch。第二天：
- `GenerationManager` 检测 `isNextDay` → expire 种子批次
- Promote NEXT batch → CURRENT
- 创建新 NEXT batch → WorkManager → DeepSeek 生成

### 新增文件

| 文件 | 角色 |
|------|------|
| `app/src/main/assets/seed_articles.json` | 15 篇种子文章 |
| `data/local/seed/SeedArticleDto.kt` | JSON 反序列化 data class（kotlinx.serialization） |
| `data/local/seed/SeedDatabase.kt` | `seedDatabase()` 工具函数，被 `Callback.onCreate` 调用 |

**注意**：`SeedDatabase.kt` 中的 `seedDatabase()` 使用 `ContentValues` + `db.insert()` 等 raw SQLite API，不经过 Room DAO。

### 修改文件

| 文件 | 修改 |
|------|------|
| `di/AppModule.kt` | `provideDatabase()` 增加 `json: Json` 参数 + `Callback.onCreate` |

## 2. DeepSeek 授权对话框

### 触发器

每次 App 启动时，`MainActivity.ContextaApp()` 在 NavGraph 之前检查。

### 判断条件

`UserSettingsEntity.deepseekAuthorized` 字段（Boolean, 默认 false）。

### UI

- 未授权时在 `ContextaApp()` 中渲染 `DeepSeekAuthDialog` 全屏 composable
- 对话框内容：标题（"需要 DeepSeek API 授权"）、说明文本、确认按钮、拒绝按钮
- 用户确认 → 写入 `deepseekAuthorized = true` → 进入 NavGraph
- 用户拒绝 → `finish()` 关闭 Activity（无 DeepSeek 无法生成内容）

### 新增/修改

| 文件 | 修改 |
|------|------|
| `data/local/entity/UserSettingsEntity.kt` | 增加 `deepseekAuthorized: Boolean = false` |
| `data/local/Migrations.kt` | 新增 Migration 1→2（ALTER TABLE ADD COLUMN） |
| `MainActivity.kt` | 增加授权门控 composable |
| 新增 `ui/auth/AuthGateViewModel.kt` | 管理授权状态流 |
| 新增 `ui/auth/DeepSeekAuthDialog.kt` | 授权对话框 composable |

## 3. Worker 日志

`ArticleGenerationWorker` 中增加 `android.util.Log` 调用：

| 路径 | 日志 |
|------|------|
| `doWork()` 成功 | `Log.i(TAG, "Worker completed successfully for batch $batchId")` |
| `doWork()` 失败 | `Log.w(TAG, "Worker failed for batch $batchId: ${e.message}")` |
| `processBatch()` 批次完成 | `Log.i(TAG, "Batch $batchId completed: ${articles.size} articles")` |
| `processBatch()` 文章生成成功 | `Log.d(TAG, "Article $articleId generated: $title")` |
| `processBatch()` 文章生成失败 | `Log.w(TAG, "Article $articleId failed: ${e::class.simpleName}")` |

## 完整影响范围

### 新增文件（5 个）

1. `app/src/main/assets/seed_articles.json`
2. `data/local/seed/SeedArticleDto.kt`
3. `data/local/seed/SeedDatabase.kt`
4. `ui/auth/AuthGateViewModel.kt`
5. `ui/auth/DeepSeekAuthDialog.kt`

### 修改文件（8 个）

1. `data/local/entity/UserSettingsEntity.kt` — 加 `deepseekAuthorized` 字段
2. `data/local/Migrations.kt` — 加 Migration 1→2
3. `data/local/ContextaDatabase.kt` — 升版本 v1→v2
4. `di/AppModule.kt` — `provideDatabase()` 加 `Callback.onCreate` + `Json` 参数
5. `domain/repository/SettingsRepository.kt` — 加 `authorizeDeepSeek()`
6. `ui/home/HomeViewModel.kt` — 等级过滤 + 篇数截断
7. `worker/ArticleGenerationWorker.kt` — 加日志
8. `domain/generation/ArticlePrompts.kt` — 导出 `categoryToDifficulty`（若尚未 public）

### 不修改的文件

- `domain/GenerationManager.kt` — 不涉及
- `navigation/NavGraph.kt` — 授权门控在 NavGraph 前
