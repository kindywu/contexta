# 种子数据 + DeepSeek 授权 + Worker 日志 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the app with 15 pre-written seed articles, a DeepSeek authorization dialog on startup, and structured worker logging — so new users see content immediately and understand how background generation works.

**Architecture:** Seed articles live in `assets/seed_articles.json` and are loaded into Room DB via `RoomDatabase.Callback.onCreate()` — a one-time insert that fires when the SQLite file is first created. DeepSeek authorization uses a new boolean on `UserSettingsEntity` gated by a composable in `MainActivity` before the NavGraph. Worker logging uses plain `android.util.Log` at info/debug levels.

**Tech Stack:** Kotlin, Room (raw `SupportSQLiteDatabase` for seed insert), kotlinx.serialization (JSON DTO), Hilt, Jetpack Compose, WorkManager.

## Global Constraints

- Seed data loading happens only in `Callback.onCreate()` — no runtime fallback
- All 15 articles use the XML format defined in `article_system.txt` (paragraph max 1-3 sentences)
- `categoryToDifficulty()` from `domain/generation/ArticlePrompts.kt` is reused for HomeViewModel filtering — no duplicate mapping
- Migration v1→v2 uses ALTER TABLE ADD COLUMN (not destructive)
- DB version must be bumped from 1 to 2
- Auth dialog is a composable, not system AlertDialog
- Auth flag persists via `UserSettingsEntity` singleton (id=1)
- Worker logs use `Log.i` for success, `Log.w` for warnings, `Log.d` for per-article details

---

### Task 1: Seed article DTOs

**Files:**
- Create: `data/local/seed/SeedArticleDto.kt`

**Interfaces:**
- Produces: `SeedDataDto` (root), `SeedArticleDto`, `SeedParagraphDto` — kotlinx.serialization data classes
- Consumes: `kotlinx.serialization.Json` (from `NetworkModule`)

- [ ] **Step 1: Create `SeedArticleDto.kt`**

```kotlin
package com.ak.contexta.data.local.seed

import kotlinx.serialization.Serializable

@Serializable
data class SeedDataDto(
    val version: Int,
    val seedArticles: List<SeedArticleDto>
)

@Serializable
data class SeedArticleDto(
    val difficultyLevel: String,
    val contentCategory: String,
    val orderIndex: Int,
    val title: String,
    val paragraphs: List<SeedParagraphDto>
)

@Serializable
data class SeedParagraphDto(
    val orderIndex: Int,
    val englishText: String,
    val chineseTranslation: String
)
```

- [ ] **Step 2: Verify compilation**

Run: `./gradlew :app:compileDebugKotlin` — expect SUCCESS.

---

### Task 2: SeedDatabase utility

**Files:**
- Create: `data/local/seed/SeedDatabase.kt`

**Interfaces:**
- Consumes: `SeedDataDto`, `android.content.ContentValues`, `android.content.Context` (for assets), `androidx.sqlite.db.SupportSQLiteDatabase`
- Produces: `seedDatabase(context, json, db)` function — called from `Callback.onCreate`

- [ ] **Step 1: Create `SeedDatabase.kt`**

```kotlin
package com.ak.contexta.data.local.seed

import android.content.ContentValues
import android.content.Context
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteQueryBuilder
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.time.ZoneId

fun seedDatabase(context: Context, json: Json, db: SupportSQLiteDatabase) {
    val jsonText = context.assets.open("seed_articles.json")
        .bufferedReader()
        .use { it.readText() }
    val seedData = json.decodeFromString<SeedDataDto>(jsonText)

    val today = LocalDate.now(ZoneId.of("Asia/Shanghai")).toString()
    val now = System.currentTimeMillis()

    db.beginTransaction()
    try {
        // Insert seed batch
        val batchValues = ContentValues().apply {
            put("batch_type", "CURRENT")
            put("status", "CURRENT")
            put("difficulty_level_snapshot", "SEED")
            put("daily_count_snapshot", 5)
            put("generated_on", today)
            put("unlocked_on", today)
            put("last_updated_at", now)
        }
        val batchId = db.insert("article_batch", ContentValues().apply {}, batchValues)

        if (batchId == -1L) {
            throw RuntimeException("Failed to insert seed article batch")
        }

        // Insert articles and paragraphs
        for (article in seedData.seedArticles) {
            val articleValues = ContentValues().apply {
                put("batch_id", batchId)
                put("order_index", article.orderIndex)
                put("content_category", article.contentCategory)
                put("title", article.title)
                put("status", "SUCCESS")
                put("generation_completed_at", now)
            }
            val articleId = db.insert("article", ContentValues().apply {}, articleValues)

            if (articleId == -1L) {
                throw RuntimeException("Failed to insert seed article: ${article.title}")
            }

            for (para in article.paragraphs) {
                val paraValues = ContentValues().apply {
                    put("article_id", articleId)
                    put("order_index", para.orderIndex)
                    put("english_text", para.englishText)
                    put("chinese_translation", para.chineseTranslation)
                }
                db.insert("article_paragraph", ContentValues().apply {}, paraValues)
            }
        }

        db.setTransactionSuccessful()
    } finally {
        db.endTransaction()
    }
}
```

- [ ] **Step 2: Verify compilation**

Run: `./gradlew :app:compileDebugKotlin` — expect SUCCESS.

---

### Task 3: AppModule callback + DB version + migration

**Files:**
- Modify: `di/AppModule.kt` — add `Callback.onCreate`
- Modify: `data/local/ContextaDatabase.kt` — version 1→2
- Modify: `data/local/Migrations.kt` — add Migration 1→2 (ALTER TABLE for `deepseekAuthorized`)
- Modify: `domain/repository/SettingsRepository.kt` — add `authorizeDeepSeek()`

- [ ] **Step 1: Update `AppModule.provideDatabase()` — add `json: Json` parameter and `Callback.onCreate`**

```kotlin
@Provides
@Singleton
fun provideDatabase(
    @ApplicationContext context: Context,
    json: Json
): ContextaDatabase {
    return Room.databaseBuilder(
        context,
        ContextaDatabase::class.java,
        "contexta.db"
    )
        .addCallback(object : Callback() {
            override fun onCreate(db: SupportSQLiteDatabase) {
                seedDatabase(context, json, db)
            }
        })
        .addMigrations(*Migrations.ALL)
        .fallbackToDestructiveMigration()
        .build()
}
```

Add imports:
```kotlin
import androidx.room.RoomDatabase.Callback
import androidx.sqlite.db.SupportSQLiteDatabase
import com.ak.contexta.data.local.seed.seedDatabase
import kotlinx.serialization.json.Json
```

- [ ] **Step 2: Bump `ContextaDatabase` version 1→2**

```kotlin
@Database(version = 2, entities = [...])
```

- [ ] **Step 3: Add Migration 1→2 in `Migrations.kt`**

```kotlin
val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE user_settings ADD COLUMN deepseek_authorized INTEGER NOT NULL DEFAULT 0")
    }
}

val ALL: Array<Migration> = arrayOf(MIGRATION_1_2)
```

- [ ] **Step 4: Add `authorizeDeepSeek()` to `SettingsRepository`**

```kotlin
suspend fun authorizeDeepSeek() {
    val existing = settingsDao.get() ?: return
    settingsDao.upsert(existing.copy(deepseekAuthorized = true))
}
```

- [ ] **Step 5: Verify compilation**

Run: `./gradlew :app:compileDebugKotlin` — expect SUCCESS.

---

### Task 4: Seed articles JSON content (15 articles)

**Files:**
- Create: `app/src/main/assets/seed_articles.json`

**Content requirements:**
- LOW (50-100 words, 3-5 paragraphs): DAILY_CONVERSATION(2), SCENE_DESCRIPTION(2), SIMPLE_STORY(1)
- MEDIUM (100-300 words, 5-10 paragraphs): NEWS(2), EXPOSITORY(1), ARGUMENTATIVE(1), PERSONAL_ESSAY(1)
- HIGH (300-600 words, 10-15 paragraphs): ACADEMIC_EXCERPT(1), DEBATE_SPEECH(1), LEGAL_DOCUMENT(1), ART_CRITICISM(1), CLASSIC_NOVEL_EXCERPT(1)

- [ ] **Step 1: Write the JSON file with all 15 articles**

The JSON follows the `SeedDataDto` schema and contains articles like:

<details>
<summary>LOW articles (50-100 words each)</summary>

```json
{
  "difficultyLevel": "LOW",
  "contentCategory": "DAILY_CONVERSATION",
  "orderIndex": 1,
  "title": "A Day at the Park",
  "paragraphs": [
    { "orderIndex": 1, "englishText": "It is a sunny day. The sky is blue and the birds are singing.", "chineseTranslation": "今天是个晴天。天空很蓝，鸟儿在唱歌。" },
    { "orderIndex": 2, "englishText": "Two friends meet at the park. They sit on a green bench.", "chineseTranslation": "两个朋友在公园见面。他们坐在一张绿色长椅上。" },
    { "orderIndex": 3, "englishText": "\"What do you want to do today?\" asks Lisa.", "chineseTranslation": "\"你今天想做什么？\"丽莎问道。" },
    { "orderIndex": 4, "englishText": "\"Let's walk around the lake,\" says Tom. They walk and talk happily.", "chineseTranslation": "\"我们绕着湖走走吧，\"汤姆说。他们边走边聊，很开心。" },
    { "orderIndex": 5, "englishText": "The day passes quickly. They promise to meet again next week.", "chineseTranslation": "一天过得很快。他们约定下周再见面。" }
  ]
}
```

Plus DAILY_CONVERSATION (第4篇), SCENE_DESCRIPTION (第2、5篇), SIMPLE_STORY (第3篇).
</details>

<details>
<summary>MEDIUM articles (100-300 words each)</summary>

Each with 6-8 paragraphs. Categories: NEWS(2), EXPOSITORY(1), ARGUMENTATIVE(1), PERSONAL_ESSAY(1).
</details>

<details>
<summary>HIGH articles (300-600 words each)</summary>

Each with 10-15 paragraphs. Categories: ACADEMIC_EXCERPT, DEBATE_SPEECH, LEGAL_DOCUMENT, ART_CRITICISM, CLASSIC_NOVEL_EXCERPT.
</details>

**Full content to be written inline when implementing.**

- [ ] **Step 2: Verify JSON is valid**

Run: `python3 -c "import json; json.load(open('impl/app/android/app/src/main/assets/seed_articles.json'))"` — expect no errors.

- [ ] **Step 3: Compile to check asset is accessible**

Run: `./gradlew :app:compileDebugKotlin` — expect SUCCESS.

---

### Task 5: UserSettingsEntity update

**Files:**
- Modify: `data/local/entity/UserSettingsEntity.kt`

- [ ] **Step 1: Add `deepseekAuthorized` field**

```kotlin
@Entity(tableName = "user_settings")
data class UserSettingsEntity(
    @PrimaryKey
    val id: Int = 1,
    @ColumnInfo(name = "is_onboarded")
    val isOnboarded: Boolean = false,
    @ColumnInfo(name = "difficulty_level")
    val difficultyLevel: String = "MEDIUM",
    @ColumnInfo(name = "daily_article_count")
    val dailyArticleCount: Int = 3,
    @ColumnInfo(name = "translation_display_mode")
    val translationDisplayMode: String = "FULL",
    @ColumnInfo(name = "mastery_threshold_n")
    val masteryThresholdN: Int = 1,
    @ColumnInfo(name = "auto_play_audio")
    val autoPlayAudio: Boolean = false,
    @ColumnInfo(name = "deepseek_authorized")
    val deepseekAuthorized: Boolean = false
)
```

- [ ] **Step 2: Verify compilation**

Run: `./gradlew :app:compileDebugKotlin` — expect SUCCESS.

---

### Task 6: Auth gate — ViewModel + Dialog composable

**Files:**
- Create: `ui/auth/AuthGateViewModel.kt`
- Create: `ui/auth/DeepSeekAuthDialog.kt`

- [ ] **Step 1: Create `AuthGateViewModel.kt`**

```kotlin
package com.ak.contexta.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed class AuthState {
    data object Loading : AuthState()
    data object Needed : AuthState()
    data object Granted : AuthState()
}

@HiltViewModel
class AuthGateViewModel @Inject constructor(
    private val settingsRepository: SettingsRepository
) : ViewModel() {

    private val _authState = MutableStateFlow<AuthState>(AuthState.Loading)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    init {
        viewModelScope.launch {
            val settings = settingsRepository.getSettings()
            _authState.value = if (settings?.deepseekAuthorized == true) {
                AuthState.Granted
            } else {
                AuthState.Needed
            }
        }
    }

    fun authorize() {
        viewModelScope.launch {
            settingsRepository.authorizeDeepSeek()
            _authState.value = AuthState.Granted
        }
    }

    fun reject() {
        _authState.value = AuthState.Needed // stays on this screen
    }
}
```

- [ ] **Step 2: Create `DeepSeekAuthDialog.kt`**

```kotlin
package com.ak.contexta.ui.auth

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@Composable
fun DeepSeekAuthDialog(
    onConfirm: () -> Unit,
    onDeny: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "需要 DeepSeek API 授权",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onBackground
            )

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Contexta 使用 DeepSeek AI 生成英语文章，帮助您在阅读中学习词汇。\n\n" +
                        "首次启动需要您确认授权使用 DeepSeek API。您的 API 密钥仅用于本应用的文章生成。",
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(32.dp))

            Button(
                onClick = onConfirm,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("授权使用")
            }

            Spacer(modifier = Modifier.height(12.dp))

            TextButton(onClick = onDeny) {
                Text("拒绝并退出", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}
```

- [ ] **Step 3: Verify compilation**

Run: `./gradlew :app:compileDebugKotlin` — expect SUCCESS.

---

### Task 7: MainActivity auth gate

**Files:**
- Modify: `MainActivity.kt`

- [ ] **Step 1: Add auth gate before NavGraph in `ContextaApp()`**

```kotlin
@Composable
private fun ContextaApp() {
    val authViewModel: AuthGateViewModel = hiltViewModel()
    val authState by authViewModel.authState.collectAsState()

    when (authState) {
        is AuthState.Loading -> {
            // Show splash / nothing
            Box(modifier = Modifier.fillMaxSize())
        }
        is AuthState.Needed -> {
            DeepSeekAuthDialog(
                onConfirm = { authViewModel.authorize() },
                onDeny = {
                    // Activity owner is the Context, but in Compose we need to close
                    // via the activity reference
                }
            )
        }
        is AuthState.Granted -> {
            val navController = rememberNavController()
            val navBackStackEntry by navController.currentBackStackEntryAsState()
            val currentRoute = navBackStackEntry?.destination?.route
            val showBottomBar = currentRoute in listOf(
                Screen.Home.route,
                Screen.Vocabulary.route,
                Screen.Reference.route,
                Screen.Settings.route
            )
            val currentTab = BottomNavTab.entries.find { it.route == currentRoute }

            Scaffold(
                modifier = Modifier.fillMaxSize(),
                bottomBar = {
                    if (showBottomBar && currentTab != null) {
                        BottomNavBar(
                            selectedTab = currentTab,
                            onTabSelected = { tab ->
                                navController.navigate(tab.route) {
                                    launchSingleTop = true
                                }
                            }
                        )
                    }
                }
            ) { innerPadding ->
                ContextaNavGraph(
                    navController = navController,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                )
            }
        }
    }
}
```

Add imports:
```kotlin
import com.ak.contexta.ui.auth.AuthGateViewModel
import com.ak.contexta.ui.auth.AuthState
import com.ak.contexta.ui.auth.DeepSeekAuthDialog
import androidx.hilt.navigation.compose.hiltViewModel
```

For the reject handler, add a `LocalContext` reference and call `finish()`:

```kotlin
val context = LocalContext.current
// ...
onDeny = { (context as? Activity)?.finish() }
```

Add import:
```kotlin
import android.app.Activity
import androidx.compose.ui.platform.LocalContext
```

- [ ] **Step 2: Verify compilation**

Run: `./gradlew :app:compileDebugKotlin` — expect SUCCESS.

---

### Task 8: HomeViewModel level filtering

**Files:**
- Modify: `ui/home/HomeViewModel.kt`

- [ ] **Step 1: Add level filtering + daily count limit in `observeCurrentBatch()`**

Replace the existing article observation block:

```kotlin
private suspend fun observeCurrentBatch() {
    val currentBatch = articleRepository.getCurrentBatch()
    if (currentBatch != null) {
        articleRepository.observeArticles(currentBatch.id)
            .map { articles ->
                val settings = settingsRepository.getSettings()

                val userDifficulty = settings?.difficultyLevel ?: "MEDIUM"
                val dailyCount = settings?.dailyArticleCount ?: Int.MAX_VALUE

                // Filter by user's difficulty level and limit by dailyCount
                val shownArticles = articles
                    .filter { it.status != ArticleStatus.PENDING }
                    .filter { categoryToDifficulty(it.contentCategory) == userDifficulty }
                    .sortedBy { it.orderIndex }
                    .take(dailyCount)

                shownArticles.map { article ->
                    ArticleItemUi(
                        id = article.id,
                        title = article.title,
                        description = article.contentCategory,
                        difficultyLabel = settings?.difficultyLevel ?: "MEDIUM",
                        categoryLabel = article.contentCategory.replace("_", " ")
                    )
                }.let { items ->
                    listOf(
                        ArticleGroupUi(
                            dateLabel = _state.value.dateLabel,
                            articles = items
                        )
                    )
                }
            }
            .collect { groups ->
                val hasContent = groups.any { it.articles.isNotEmpty() }
                _state.value = _state.value.copy(
                    articleGroups = groups,
                    isLoading = false,
                    isGenerating = !hasContent,
                    generationMessage = if (!hasContent) "当前等级暂无文章" else ""
                )
            }
    } else {
        _state.value = _state.value.copy(isLoading = false)
    }
}
```

Add import:
```kotlin
import com.ak.contexta.domain.generation.categoryToDifficulty
```

- [ ] **Step 2: Verify compilation**

Run: `./gradlew :app:compileDebugKotlin` — expect SUCCESS.

---

### Task 9: Worker logging

**Files:**
- Modify: `worker/ArticleGenerationWorker.kt`

- [ ] **Step 1: Add logging throughout ArticleGenerationWorker**

```kotlin
import android.util.Log

private const val TAG = "ArticleGenWorker"

// In doWork():
override suspend fun doWork(): Result {
    val batchId = inputData.getLong(KEY_BATCH_ID, -1L)
    if (batchId == -1L) {
        Log.w(TAG, "doWork called without batchId")
        return Result.failure()
    }

    val appVersionCode = inputData.getInt(KEY_APP_VERSION_CODE, 0)
    Log.i(TAG, "doWork: batchId=$batchId, appVersionCode=$appVersionCode")

    if (!articleRepository.claimBatch(batchId)) {
        Log.i(TAG, "Batch $batchId already claimed by another worker")
        return Result.success()
    }

    return try {
        processBatch(batchId, appVersionCode)
        Log.i(TAG, "Batch $batchId completed successfully")
        Result.success()
    } catch (e: PipelineBlockingException) {
        Log.w(TAG, "Batch $batchId blocked: ${e.message}")
        articleRepository.markBatchBlocked(batchId, e.message ?: "Unknown", appVersionCode)
        Result.failure()
    } catch (e: Exception) {
        Log.w(TAG, "Batch $batchId unexpected error: ${e.message}", e)
        if (runAttemptCount < 2) {
            Result.retry()
        } else {
            Result.failure()
        }
    }
}

// In processBatch article loop, before try block:
Log.d(TAG, "Processing article ${article.id} (${article.contentCategory})")

// After completeArticle:
Log.d(TAG, "Article ${article.id} generated: $title")

// In each catch block:
Log.w(TAG, "Article ${article.id} failed: ${e::class.simpleName}")

// After batch completion check:
if (articleRepository.isBatchComplete(batchId)) {
    articleRepository.markBatchReady(batchId)
    Log.i(TAG, "Batch $batchId all ${articles.size} articles ready")
}
```

- [ ] **Step 2: Verify compilation**

Run: `./gradlew :app:compileDebugKotlin` — expect SUCCESS.

---

### Self-Review Checklist

- [ ] **Seed data covers spec**: 15 articles, 5 per difficulty level, each with correct content categories
- [ ] **Seed loading only in `Callback.onCreate()`**: no runtime fallback in HomeViewModel
- [ ] **Level filtering**: `categoryToDifficulty()` matches user's `difficultyLevel` setting
- [ ] **Daily count limit**: `take(dailyCount)` applied after level filtering
- [ ] **Auth dialog on startup**: `AuthState.Loading → Needed/Granted` in `MainActivity.ContextaApp()`
- [ ] **Auth persisted**: `deepseekAuthorized` boolean in `UserSettingsEntity`, Migration v1→2
- [ ] **Worker logs**: success/failure at info level, per-article at debug
- [ ] **No placeholders**: every code block above is complete and compilable
- [ ] **Type consistency**: `categoryToDifficulty()` signature matches what exists in `ArticlePrompts.kt`, `SeedDataDto` fields match JSON layout
