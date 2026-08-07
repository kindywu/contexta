# Contexta Android → Flutter 迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `impl/app/flutter` 用 Flutter/drift/Riverpod 复刻 Android 版 Contexta 全部功能，数据库 schema 与数据完全一致，验收通过后删除 `impl/app/android`。

**Architecture:** 沿用原分层（data / domain / ui / worker / monitoring），技术栈替换：Room→drift、ViewModel→Riverpod、Retrofit→dio、WorkManager→flutter_workmanager、系统 TTS→KittenTTS(默认)+flutter_tts(兜底)。数据库通过 user_version 对齐（均为 1）+ 同包名同库文件实现"旧数据直接可用"。

**Tech Stack:** Flutter(≥3.22) / Dart(≥3.4) / drift(+drift_flutter, drift_dev, build_runner) / flutter_riverpod / dio / flutter_workmanager / flutter_tts / kittentts / audioplayers / crypto / go_router / path_provider。Android minSdk 29（沿用原版）、iOS 16+（KittenTTS 要求）。

## Global Constraints

- **包名**：Android applicationId / iOS bundle id 均为 `com.ak.contexta`（flutter create `--org com.ak --project-name contexta`）
- **数据库**：文件名 `contexta.db`；drift `schemaVersion = 1`；所有 Table 类**禁用 `withDefault()`**；`beforeOpen` 必须 `PRAGMA foreign_keys = ON`
- **存储格式**：日期 `yyyy-MM-dd`；日期时间 `yyyy-MM-dd'T'HH:mm:ssXXX`（本机时区偏移，手写格式化，不用 intl 的冒号缺失偏移）；Unix 毫秒仅 `article_batch.ready_notified_at`、`generation_error_log.notified_at`；枚举一律 TEXT 存枚举名（大写）；Boolean 存 0/1
- **每批固定 5 篇文章**；`findNextReadyBatch` 只找 `generated_on > maxRefDate`；题材轮换偏移 = `(nowMillis % 1000) % 类别数`；每天每难度只生成一批
- **LLM**：非流式 `POST {baseUrl}/v1/chat/completions`，`model=deepseek-v4-flash`、`temperature=0.7`、`max_tokens=16384`、`stream=false`；超时 120s（.timeout + 不取消父协程）、重试 3 次（429 用 Retry-After 封顶 30s，否则指数退避 2/4/8s）、CancellationException 立即传播；错误三分类 Structural/Fatal/Recoverable
- **TTS**：KittenTTS 默认（模型 nano-int8 打包 assets）、初始化失败自动回退 flutter_tts（引擎链：小米 miBrain → Google → 默认）；语速 UI 1x/0.75x → 系统兜底 rate 0.70f/0.45f
- **飞书告警**：HMAC-SHA256(key=timestamp-30s+"\n"+secret, data="")→Base64→URL 编码；必须解析响应体业务 code；同 `prefix_errorCode_batchId` 5 分钟内存去重；送达才回写 notified_at/ready_notified_at；补发限 24h
- **密钥**：`--dart-define-from-file=local.properties`，键映射：`deepseek.apiKey→DEEPSEEK_API_KEY`、`deepseek.baseUrl→DEEPSEEK_BASE_URL`、`feishu.webhookUrl→FEISHU_WEBHOOK_URL`、`feishu.signSecret→FEISHU_SIGN_SECRET`、`llmTimeoutMs→LLM_TIMEOUT_MS`（默认 120000）
- **迁移来源**：所有 Kotlin 文件（`impl/app/android/app/src/main/java/com/ak/contexta/**`）与 Kotlin 测试（`impl/app/android/app/src/test/**`）为权威参考；每任务均标注"参照"路径
- **提交**：每个任务独立 commit，消息 `feat|test|chore|docs:` 前缀；临时文档（temp_docs 类）不入库
- **测试命令**：`flutter analyze` + `flutter test test/<path>`；每任务 TDD（先写测试→看失败→实现→通过→提交）

---

## Phase 0：脚手架与基础

### Task 1: Flutter 项目脚手架

**Files:**
- Create: `impl/app/flutter/`（flutter create 生成）
- Modify: `impl/app/flutter/pubspec.yaml`、`impl/app/flutter/lib/main.dart`、`impl/app/flutter/android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces: 可运行的空 Flutter 工程（`flutter analyze` 零错误、`flutter test` 通过），后续所有任务在此目录内进行

- [ ] **Step 1: flutter create**

```bash
cd /Users/kindy/Githubs/contexta/impl/app
flutter create --org com.ak --project-name contexta --platforms android,ios --empty flutter
```

- [ ] **Step 2: 添加依赖**

```bash
cd flutter
flutter pub add drift drift_flutter sqlite3_flutter_libs flutter_riverpod dio flutter_workmanager flutter_tts audioplayers crypto path_provider go_router
flutter pub add dev:drift_dev dev:build_runner dev:test
flutter pub add kittentts   # pub.dev 上该包（KittenML）
```

- [ ] **Step 3: Android 配置（minSdk 29 + 权限 + 应用名）**

编辑 `android/app/build.gradle.kts`：`minSdk = 29`（drift sqlite3 与 KittenTTS 兼容）。
编辑 `android/app/src/main/AndroidManifest.xml` 加：

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<queries>
  <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
  <package android:name="com.xiaomi.mibrain.speech"/>
  <package android:name="com.google.android.tts"/>
</queries>
```

应用名改为 `Contexta`（参照原版 `impl/app/android/app/src/main/res/values/strings.xml` 的 app_name）。

- [ ] **Step 4: assets 配置**

`pubspec.yaml` 加：
```yaml
flutter:
  assets:
    - assets/seed_articles.json
    - assets/prompts/
    - assets/kittentts_models/
```
复制：`impl/app/android/app/src/main/assets/seed_articles.json` → `flutter/assets/seed_articles.json`；`impl/app/android/app/src/main/resources/prompts/`（article_system.txt + word_lookup_system.txt）→ `flutter/assets/prompts/`。

- [ ] **Step 5: 密钥读取工具**

Create: `lib/core/config/app_config.dart`：
```dart
class AppConfig {
  static const deepSeekApiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
  static const deepSeekBaseUrl = String.fromEnvironment('DEEPSEEK_BASE_URL', defaultValue: 'https://api.deepseek.com');
  static const feishuWebhookUrl = String.fromEnvironment('FEISHU_WEBHOOK_URL');
  static const feishuSignSecret = String.fromEnvironment('FEISHU_SIGN_SECRET');
  static const llmTimeoutMs = int.fromEnvironment('LLM_TIMEOUT_MS', defaultValue: 120000);
}
```
Create: `lib/core/time/iso8601.dart`（全库统一时间格式化，之后所有任务用它）：
```dart
/// yyyy-MM-dd（本地日期）
String isoLocalDate(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// yyyy-MM-dd'T'HH:mm:ss+HH:MM（本地时区偏移，与 Room 的 DateTimeFormatter.ISO_OFFSET_DATE_TIME 一致）
String isoOffsetDateTime(DateTime t) {
  final offset = t.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final a = offset.abs();
  final h = (a.inHours).toString().padLeft(2, '0');
  final m = (a.inMinutes % 60).toString().padLeft(2, '0');
  final hms = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  return '${isoLocalDate(t)}T$hms$sign$h:$m';
}

/// Unix 毫秒
int nowMillis() => DateTime.now().millisecondsSinceEpoch;
```

- [ ] **Step 6: 验证**

Run: `cd impl/app/flutter && flutter analyze && flutter test`
Expected: analyze 0 issues；默认 smoke test 通过。

- [ ] **Step 7: Commit**

```bash
git add impl/app/flutter pubspec.lock
git commit -m "chore: Flutter 项目脚手架（包名 com.ak.contexta + 依赖 + assets + 配置）"
```

### Task 2: 领域模型层

**Files:**
- Create: `lib/domain/model/article.dart`、`article_batch.dart`、`vocab_word.dart`、`word_detail.dart`、`user_settings.dart`、`daily_stats.dart`、`generation_error.dart`、`daily_learning_info.dart`
- Test: `test/domain/model/models_test.dart`

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/domain/model/*.kt`（8 个文件）

**Interfaces:**
- Produces: `Article{id,batchId,orderIndex,contentCategory,title,status,generationStartedAt?,generationCompletedAt?,retryCount,accumulatedReadSeconds,readCompletedAt?,lastRetryAt?,maxRetries,nextRetryAt?}`、`ArticleBatch{id,status,difficultyLevelSnapshot,generatedOn,lastUpdatedAt,blockedReason?,blockedAt?,readyNotifiedAt?}`、`UserSettings{isOnboarded,difficultyLevel,dailyArticleCount,translationDisplayMode,masteryThresholdN,autoPlayAudio}` 等 —— 字段与 Kotlin 完全一致（String? 对应 String?，枚举用 Dart enum，`toDbValue()`/`fromDbValue()` 存枚举名 TEXT）
- 枚举：`BatchStatus{PENDING,GENERATING,READY,CURRENT,BLOCKED}`、`ArticleStatus{PENDING,GENERATING,SUCCESS,TIMEOUT,FAILED,FATAL}`、`DifficultyLevel{LOW,MEDIUM,HIGH}`、`TranslationDisplayMode{FULL,BLURRED,HIDDEN}`（注意原版 DIM 仅 UI 用）、`VocabularyStatus{NEW,LEARNING,MASTERED}`、`ContentCategory`（原版 `ContentCategory.kt` 全部值）

- [ ] **Step 1: 写失败测试** — 对照 Kotlin 每个枚举的 `fromDbValue` 边界（未知字符串抛异常或返回默认，与 Kotlin 一致）

```dart
// test/domain/model/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:contexta/domain/model/article_status.dart';

void main() {
  test('ArticleStatus.fromDbValue 解析枚举名', () {
    expect(ArticleStatus.fromDbValue('TIMEOUT'), ArticleStatus.timeout);
    expect(ArticleStatus.fromDbValue('SUCCESS'), ArticleStatus.success);
  });
  test('未知枚举值抛异常', () {
    expect(() => ArticleStatus.fromDbValue('XXX'), throwsArgumentError);
  });
}
```

- [ ] **Step 2: 运行确认失败** — `flutter test test/domain/model/models_test.dart` → FAIL（类不存在）
- [ ] **Step 3: 实现 8 个模型类** — 字段/枚举/toString 逐一对照 Kotlin；时间字段全部用 String（ISO 字符串，与 DB 一致，不做 DateTime 转换）
- [ ] **Step 4: 测试通过** — `flutter test test/domain/model/` → PASS
- [ ] **Step 5: Commit** — `git add lib/domain test/domain && git commit -m "feat: 领域模型层（8 模型 + 枚举）"`

### Task 3: 错误体系

**Files:**
- Create: `lib/domain/error/app_error.dart`、`domain_result.dart`、`llm_exceptions.dart`、`pipeline_blocking_exception.dart`
- Test: `test/domain/error/errors_test.dart`

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/domain/error/*.kt`（4 文件）

**Interfaces:**
- Produces: `sealed class AppError`（与 Kotlin sealed 层级一致）；`class DomainResult<T>` 带 `isSuccess`/`dataOrNull`；`class LlmFatalException implements Exception`、`class LlmTimeoutException`、`class LlmRecoverableExhaustedException`、`class PipelineBlockingException`（message 字段保留，错误分类正则依赖它）

- [ ] **Step 1: 写失败测试** — 对照 Kotlin `DomainResultTest` 语义：success/failure 分支、LlmExceptions 的 message 透传
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — 逐文件对照 Kotlin；`PipelineBlockingException` 保留原 message 内容（"Constraint"/"disk I/O" 关键词由 LlmErrorClassifier 判断，Task 13）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: 错误体系（AppError/DomainResult/LLM 异常/管道阻塞）`

---

## Phase 1：数据层（drift）

### Task 4: drift 基建 + 基础表组（7 张）

**Files:**
- Create: `lib/data/local/database.dart`（`AppDatabase` + `@DriftDatabase`）、`lib/data/local/tables/settings_tables.dart`（user_settings、config_change_log、schema_migration_log、generation_pipeline_status、daily_learning_log、learning_stats_summary、daily_learning）
- Test: `test/data/local/schema_base_tables_test.dart`

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/data/local/entity/`（7 个对应文件）+ 探索报告 2.1/2.2/2.10/2.11/2.12/2.14/2.15 节

**Interfaces:**
- Produces: drift Table 类（命名复数，`@DataClassName` 单数）：`UserSettings`(表 user_settings)、`ConfigChangeLogs`、`SchemaMigrationLogs`、`GenerationPipelineStatuses`、`DailyLearningLogs`、`LearningStatsSummaries`、`DailyLearnings`；`AppDatabase` 持 `GeneratedDatabase` mixin

- [ ] **Step 1: 配置 drift 代码生成**

`pubspec.yaml` 已含 drift_dev/build_runner。Create `lib/data/local/tables/` 后运行 `dart run build_runner build -d`（生成 `database.g.dart`）。drift 版本对应 `pubspec.lock` 中 drift_dev 主版本一致。

- [ ] **Step 2: 写失败测试**（先定表结构）— 用内存库验证 7 张表可建、关键列类型正确

```dart
// test/data/local/schema_base_tables_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contexta/data/local/database.dart';

void main() {
  test('user_settings 表结构', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('PRAGMA table_info(user_settings)').get();
    final rows = await db.customSelect(
      "SELECT name, type, \"notnull\", pk FROM pragma_table_info('user_settings')",
    ).get();
    final map = {for (final r in rows) r.read<String>('name'): r};
    expect(map['id']!.read<String>('type'), 'INTEGER');
    expect(map['is_onboarded']!.read<String>('type'), 'INTEGER');
    expect(map['difficulty_level']!.read<String>('type'), 'TEXT');
    expect(map['difficulty_level']!.read<int>('notnull'), 1);
    expect(map['id']!.read<int>('pk'), 1);
  });
  // 其余 6 张表同样断言关键列（对照探索报告 2.2/2.10/2.11/2.12/2.14/2.15）
}
```

- [ ] **Step 3: 运行确认失败** — `flutter test test/data/local/schema_base_tables_test.dart` → FAIL（无 AppDatabase）
- [ ] **Step 4: 实现 7 张表** — 逐列对照 Room schema（探索报告为蓝本，实体源码为准）。同时提供测试辅助构造：

```dart
// database.dart 内
@DriftDatabase(tables: [UserSettings, ConfigChangeLogs, ...])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.forTesting(QueryExecutor e) : super(e); // 测试用，不走 MigrationStrategy/种子
}
```

```dart
// lib/data/local/tables/settings_tables.dart 示例（user_settings）
@DataClassName('UserSettingsRow')
class UserSettings extends Table {
  IntColumn get id => integer()(); // Room: id INTEGER PRIMARY KEY NOT NULL（无 autoincrement）
  BoolColumn get isOnboarded => boolean()();
  TextColumn get difficultyLevel => text()(); // 枚举存 TEXT 枚举名
  IntColumn get dailyArticleCount => integer()();
  TextColumn get translationDisplayMode => text()();
  IntColumn get masteryThresholdN => integer()();
  BoolColumn get autoPlayAudio => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}
// 注意：learning_stats_summary / generation_pipeline_status 同样 id 无 autoincrement
// daily_learning: TextColumn learningDate => text(); 主键 {learningDate}；
//   refBatchDate text()(); refBatchId integer().references(ArticleBatches, #id, onDelete: KeyAction.cascade)(); dailyCountSnapshot integer()();
//   索引：@TableIndex(name: 'index_daily_learning_ref_batch_id', columns: {refBatchId})
```

- [ ] **Step 5: 测试通过** — `flutter test test/data/local/schema_base_tables_test.dart` → PASS
- [ ] **Step 6: Commit** — `feat: drift 基础表组（7 张）+ schema 测试`

### Task 5: 文章表组（3 张）+ 生成日志表（1 张）

**Files:**
- Create: `lib/data/local/tables/article_tables.dart`（article_batch、article、article_paragraph、generation_error_log）
- Test: `test/data/local/schema_article_tables_test.dart`

**参照:** 探索报告 2.3/2.4/2.5/2.13 节 + `entity/` 4 文件

**Interfaces:**
- Produces: `ArticleBatches`、`Articles`、`ArticleParagraphs`、`GenerationErrorLogs` 表类（命名/列/索引/外键如下）

- [ ] **Step 1: 写失败测试** — 断言：article_batch 的 UNIQUE 索引 `index_article_batch_difficulty_level_snapshot_generated_on`、普通索引 `index_article_batch_generated_on`；article 的 FK `batch_id REFERENCES article_batch(id) ON DELETE CASCADE`（用 `PRAGMA foreign_key_list(article)` 断言 `on_delete=CASCADE`、`from=batch_id`、`table=article_batch`）；article_paragraph UNIQUE 索引；generation_error_log 双索引

```dart
test('article 外键 CASCADE', () async {
  final rows = await db.customSelect("PRAGMA foreign_key_list('article')").get();
  final fk = rows.first;
  expect(fk.read<String>('from'), 'batch_id');
  expect(fk.read<String>('table'), 'article_batch');
  expect(fk.read<String>('on_delete'), 'CASCADE');
});
test('article_batch UNIQUE 索引', () async {
  final rows = await db.customSelect(
    "SELECT name, \"unique\" FROM pragma_index_list('article_batch')").get();
  final map = {for (final r in rows) r.read<String>('name'): r.read<int>('unique')};
  expect(map['index_article_batch_difficulty_level_snapshot_generated_on'], 1);
  expect(map['index_article_batch_generated_on'], 0);
});
```

- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现 4 张表** — 注意：`ArticleBatches.readyNotifiedAt` 为 `integer()`（Unix 毫秒，可空）；`Articles` 全部时间列 `text()` 可空；`@TableIndex(name: 'index_article_batch_id', columns: {batchId})`；`Articles.batchId` 外键 CASCADE；`ArticleParagraphs.articleId` 外键 CASCADE + UNIQUE 索引 `index_article_paragraph_article_id_order_index`
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: drift 文章/生成日志表组（4 张）+ schema 测试`

### Task 6: 词库表组（4 张）

**Files:**
- Create: `lib/data/local/tables/word_tables.dart`（word、word_sense、example_sentence、vocabulary_entry）
- Test: `test/data/local/schema_word_tables_test.dart`

**参照:** 探索报告 2.6/2.7/2.8/2.9 节 + `entity/` 4 文件

**Interfaces:**
- Produces: `Words`、`WordSenses`、`ExampleSentences`、`VocabularyEntries` 表类

- [ ] **Step 1: 写失败测试** — 断言：word.spelling_normalized UNIQUE 索引 `index_word_spelling_normalized`；word_sense/example_sentence 外键 CASCADE + 普通索引；vocabulary_entry 软删除列（deleted_at、deleted_reason 可空 text）

```dart
test('word UNIQUE 索引', () async {
  final rows = await db.customSelect(
    "SELECT name, \"unique\" FROM pragma_index_list('word')").get();
  expect(rows.single.read<String>('name'), 'index_word_spelling_normalized');
  expect(rows.single.read<int>('unique'), 1);
});
```

- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现 4 张表** — `Words` 主键 autoincrement；`WordSenses.orderIndex` 等列名注意 snake_case 由 drift 自动生成；`ExampleSentences.isPrimary` 用 `boolean()`；`VocabularyEntries` 含 status、correctReviewStreak、masteredAt?、deletedAt?、deletedReason?；3 条外键 CASCADE
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: drift 词库表组（4 张）+ schema 测试`

### Task 7: 数据库打开策略 + 种子数据

**Files:**
- Create: `lib/data/local/database_open.dart`（`buildAppDatabase()`，含 MigrationStrategy）、`lib/data/local/seed/seed_database.dart`、`lib/data/local/seed/seed_article.dart`
- Modify: `lib/data/local/database.dart`（挂 MigrationStrategy）
- Test: `test/data/local/seed_test.dart`
- Assets: `assets/seed_articles.json`（Task 1 已复制）

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/di/AppModule.kt:40-53`（onCreate 回调）+ `seed/SeedDatabase.kt` + `seed/SeedArticle.kt` + `assets/seed_articles.json`

**Interfaces:**
- Produces: `Future<AppDatabase> buildAppDatabase({String? overridePath})`；`Future<void> writeSeedIfNeeded(AppDatabase db)`

- [ ] **Step 1: 写失败测试** — 全新内存库打开后：种子批次 3 条（LOW/MEDIUM/HIGH、status=READY、generated_on="2026-03-29"）、文章 15 条、段落 105 条；user_settings 不写入

```dart
test('全新库写入种子', () async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await writeSeedIfNeeded(db);
  final batches = await (db.select(db.articleBatches)..where((t) => t.generatedOn.equals('2026-03-29'))).get();
  expect(batches.length, 3);
  expect(batches.map((b) => b.status).toSet(), {'READY'});
  final articles = await db.select(db.articles).get();
  expect(articles.length, 15);
  expect((await db.select(db.articleParagraphs).get()).length, 105);
});
```

- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — `writeSeedIfNeeded` 检查 `article_batch` 表为空才写（事务包裹）；JSON 用 `dart:convert` 解析（结构 `{version, seedArticles:[{difficultyLevel, contentCategory, orderIndex, title, paragraphs:[{orderIndex, englishText, chineseTranslation}]}]}`）；批次 `last_updated_at = isoOffsetDateTime(DateTime(2026,3,29,12,0))`（与原版 `dateTimeStringAt(2026,3,29,12,0)` 等价）；文章 `status='SUCCESS'`、`retry_count=0`、`max_retries=3`、`accumulated_read_seconds=0`
- [ ] **Step 4: 打开策略** — `buildAppDatabase()`：

```dart
Future<AppDatabase> buildAppDatabase({String? overridePath}) {
  final db = AppDatabase._open(
    NativeDatabase.createInBackground(File(overridePath ?? await _dbPath())),
    migrationStrategy: MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await writeSeedIfNeeded(db); // 全新库才走到这（等价 Room onCreate）
      },
      beforeOpen: (details) async {
        await db.customStatement('PRAGMA foreign_keys = ON'); // Room 默认开启，必须对齐
      },
    ),
  );
  return db;
}
// _dbPath(): 用 path_provider 的 getApplicationSupportDirectory() 或 getDatabasesPath()
// 必须与 Android 原路径等价：databases/contexta.db（getApplicationSupportDirectory 在 Android = files 目录，
// 需在原生侧把数据库目录对齐 —— 见 Task 18 的平台通道/壳配置验证；若 drift_flutter 的 driftDatabase(name:)
// 路径即 /files/databases/contexta.db，与原版 getDatabasePath 的 /databases/contexta.db 相同目录）
```

> **关键验证点**：`getDatabasePath("contexta.db")` 在 Android 返回 `databases/contexta.db`（data/data/<pkg>/databases/）。drift 的 `NativeDatabase.createInBackground` 需指向同一路径。Task 8 用真机备份库验证此路径语义。

- [ ] **Step 5: 测试通过**
- [ ] **Step 6: Commit** — `feat: 数据库打开策略（FK 开启 + 种子写入）`

### Task 8: 数据库兼容验证（备份真机库）

**Files:**
- Create: `test/data/local/legacy_db_compat_test.dart`
- Test fixture: 复制 `.backup/contexta-db-2026-08-07/`（db+wal+shm）到 `test/fixtures/legacy/`（wal/shm 测试时用临时副本合并）

**参照:** 探索报告"数据库一致性验收"硬性步骤

**Interfaces:**
- Verifies: drift 打开旧 Room 库 → 数据完整可读 + schema 逐项语义比对

- [ ] **Step 1: 准备 fixture**

```bash
mkdir -p impl/app/flutter/test/fixtures/legacy
cp .backup/contexta-db-2026-08-07/contexta.db impl/app/flutter/test/fixtures/legacy/
# wal/shm 不复制（测试时用 checkpoint 后单文件，SQLite 自动重放已在备份验证时做过）
```

- [ ] **Step 2: 写测试** — 打开旧库（只读复制到临时目录，避免污染 fixture）：

```dart
test('drift 打开旧 Room 库：数据可读', () async {
  final tmp = await Directory.systemTemp.createTemp('legacy-db');
  File('test/fixtures/legacy/contexta.db').copySync('${tmp.path}/contexta.db');
  final db = await buildAppDatabase(overridePath: '${tmp.path}/contexta.db');
  // user_version 应为 1（drift schemaVersion 匹配，不触发迁移/重建）
  final v = await db.customSelect('PRAGMA user_version').getSingle();
  expect(v.read<int>('user_version'), 1);
  // 真实数据可读
  expect((await db.select(db.articleBatches).get()).length, 12);
  expect((await db.select(db.articles).get()).length, 60);
  expect((await db.select(db.articleParagraphs).get()).length, 550);
  expect((await db.select(db.words).get()).length, 10);
  // 外键开启
  final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
  expect(fk.read<int>('foreign_keys'), 1);
});
test('drift 打开旧库：不重建（sqlite_sequence 保留）', () async {
  // 打开前记录 user_settings 的 rowid，打开后仍可读且 id 不变
});
```

- [ ] **Step 3: 运行确认失败**（buildAppDatabase 尚未实现路径逻辑或 drift 表结构与旧库不匹配会在此暴露）
- [ ] **Step 4: 修复直至通过** — 逐列比对失败时对照探索报告修正 Table 类（不要用 destructive 手段掩盖）
- [ ] **Step 5: 真机路径验证** — 用 adb 把备份库 push 回设备 `databases/` 目录，装 debug 包后确认 App 首页读到历史数据（12 批次等）。若路径不一致，在 Task 18 用平台通道或壳代码对齐 `getDatabasePath` 语义
- [ ] **Step 6: Commit** — `test: 旧 Room 库兼容验证（真实数据 + schema 语义比对）`

### Task 9: DAO 基础组（settings/stats/daily/config/logs）

**Files:**
- Create: `lib/data/local/daos/settings_daos.dart`（UserSettingsDao、ConfigChangeLogDao、SchemaMigrationLogDao、GenerationPipelineStatusDao、DailyLearningDao、DailyLearningLogDao、LearningStatsSummaryDao）
- Test: `test/data/local/daos/settings_daos_test.dart`

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/data/local/dao/` 7 个 DAO

**Interfaces:**
- Produces: `UserSettingsDao{getSettings, upsertSettings, completeOnboarding(level,count)}`；`DailyLearningDao{getTodayByDate, getMaxRefBatchDate, assignBatchForToday, getDailyCountSnapshot, getDailyLearningInfo...}`（对照 Kotlin 全方法）；`LearningStatsSummaryDao{get, recordArticleRead, recordWordAdded, recordWordMastered, ...}`；流水日志 DAO 的 `insert`/`getPending(24h)` 等

- [ ] **Step 1: 写失败测试**（内存库 + 种子空库）— 对照 Kotlin DAO 测试语义：
  - `assignBatchForToday` 幂等：同一天重复调用只 1 条
  - `getMaxRefBatchDate` 无记录返回 null
  - stats upsert：recordWordAdded 使 total_words_added +1
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — drift DAO 类（`@DriftAccessor` 或直接 mixin 方法）；插入注意**无 withDefault** → Dart 侧必须显式提供所有 NOT NULL 列默认值（对照 Kotlin 实体构造默认值：如 batch status='PENDING' 等，逐一从 entity 源码抄）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: DAO 基础组（settings/stats/daily/config/logs）`

### Task 10: DAO 文章组（CAS 认领 + 孤儿修复）

**Files:**
- Create: `lib/data/local/daos/article_daos.dart`（ArticleBatchDao、ArticleDao、ArticleParagraphDao、GenerationErrorLogDao）
- Test: `test/data/local/daos/article_daos_test.dart`

**参照:** `ArticleBatchDao.kt`、`ArticleDao.kt`、`ArticleParagraphDao.kt`、`GenerationErrorLogDao.kt` + 探索报告 1.2 节

**Interfaces:**
- Produces: `ArticleBatchDao{claimForGeneration(id), markReady(id), markBlocked(id, reason), getUnassignedReadyBatches(level, afterDate), getBatchByDifficultyAndDate(level, date), getGeneratingBatches, ...}`；`ArticleDao{claimForGeneration(id), completeArticle(id, retryCount?), markSuccess, markFailed(id, status, errorCode, errorMessage, retryCount), markFatal, markReadCompleted, addReadSeconds, resetOrphans, findByBatchId, ...}`；`ArticleParagraphDao{replaceParagraphs(articleId, List), getByArticleId}`；`GenerationErrorLogDao{insert, getPendingSince, markNotified, ...}`

- [ ] **Step 1: 写失败测试** — 关键 CAS 语义（对照 Kotlin SQL，测试用例逐一移植 `ArticleDaoTest` 等）：

```dart
test('claimForGeneration CAS：PENDING 可认领，SUCCESS 不可', () async {
  // 造 1 条 PENDING 文章 + 1 条 SUCCESS 文章
  // expect(claimForGeneration(pendingId), true); expect(claimForGeneration(successId), false);
});
test('claimForGeneration 认 GENERATING（中断恢复）', () async {
  // GENERATING 文章可再次认领，generation_started_at 不变
});
test('resetOrphans 单事务三重置', () async {
  // GENERATING 文章→PENDING(清 retry_count/started_at)；TIMEOUT/FAILED→PENDING；GENERATING 批次→PENDING
});
```

- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — 每条 CAS 用 drift `customUpdate` 或 `update(Table)..where(实际条件)` 保证原子性；`markFailed` 的「状态更新 + error_log 插入」必须同事务（`db.transaction`）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: DAO 文章组（CAS 认领/孤儿修复/事务）`

### Task 11: DAO 词库组

**Files:**
- Create: `lib/data/local/daos/word_daos.dart`（WordDao、WordSenseDao、ExampleSentenceDao、VocabularyEntryDao）
- Test: `test/data/local/daos/word_daos_test.dart`

**参照:** 对应 4 个 Kotlin DAO

**Interfaces:**
- Produces: `WordDao{findBySpelling, findDetailBySpelling, insertWord, ...}`（3-tier 查词第 2 层）；`VocabularyEntryDao{getActiveWords, addEntry, markCorrect, markMastered, softRemove, isInVocabulary, countActive...}`；sense/example 的批量读写

- [ ] **Step 1: 写失败测试** — 移植 Kotlin 用例：软删除语义（softRemove 后 getActiveWords 不含但 isInVocabulary 处理同 Kotlin）；markCorrect 阈值流转（连续 correctReviewStreak 达 masteryThresholdN → MASTERED + mastered_at）；无重复插入（spelling_normalized 唯一）
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: DAO 词库组`

### Task 12: 仓储层（5 个）

**Files:**
- Create: `lib/data/repository/article_repository_impl.dart`、`word_repository_impl.dart`、`vocabulary_repository_impl.dart`、`settings_repository_impl.dart`、`stats_repository_impl.dart`、`lib/domain/repository/*.dart`（5 个接口）
- Test: `test/data/repository/repositories_test.dart`

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/data/repository/*.kt` + `domain/repository/*.kt`

**Interfaces:**
- Produces: `ArticleRepository{observeArticles(level, displayLimit), findNextReadyBatch, assignBatchForToday, createBatch+articles, reconcileOrphanArticles, getUnassignedReadyBatches, getBatchByDifficultyAndDate, ...}`；`WordRepository{lookupWord(spelling)}`（3-tier：LRU(50) → DB → LLM(信号量 3) → 落库回填）；`VocabularyRepository{...}`；`SettingsRepository{getSettings(Flow), updateLevel, updateDailyCount, updateTranslationMode, updateMasteryThreshold, updateAutoPlay, completeOnboarding}`；`StatsRepository{getDailyStats, recordReadingActivity, ...}`
- **依赖注入**：`lib/di/*.dart` — Riverpod providers（`databaseProvider`、各 repositoryProvider、`dispatcherProvider` 等），Task 13/17 使用

- [ ] **Step 1: 写失败测试** — 用 Fake LLM（移植 `LlmTestClient.kt` 语义）测 3-tier：DB 命中不调 LLM；DB 未命中调 LLM 并落库；LLM 失败返回错误
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — LRU 缓存用 `LinkedHashMap` 手动实现（50 条）；信号量 `Semaphore(3)`；观察流用 drift `watch()`（对照原 Flow 语义：首页列表流）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: 仓储层（5 仓储 + Riverpod DI）`

---

## Phase 2：领域逻辑

### Task 13: LLM 客户端（dio + 超时/重试/分类）

**Files:**
- Create: `lib/data/remote/deepseek_api.dart`、`llm_caller.dart`、`dto/chat_request.dart`、`dto/chat_response.dart`、`lib/domain/llm_client.dart`、`lib/domain/llm_error_classifier.dart`
- Test: `test/data/remote/llm_caller_test.dart`、`test/domain/llm_error_classifier_test.dart`

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/data/remote/*.kt` + `domain/LlmClient.kt` + `domain/LlmErrorClassifier.kt` + `LlmCallerTest.kt`（**逐用例移植**）

**Interfaces:**
- Produces: `class LlmCaller implements LlmClient { Future<String?> call(String systemPrompt, String userPrompt, {Duration? timeoutMs}); }` — 返回 null 表示超时（不抛），异常由分类器处理；`class LlmErrorClassifier { LlmCallOutcome classify(httpCode, Object e); }`；`enum LlmCallOutcome { structural, fatal, recoverable }`

- [ ] **Step 1: 写失败测试**（移植 `LlmCallerTest.kt` 全部用例，用 `dio` 的 MockAdapter 或注入 `http.Client` fake）：

```dart
test('超时返回 null 且不重试', () async {
  // fake client 永远挂起 > timeout → call() 返回 null（不抛、不计 retry）
});
test('HTTP 401 → 立即抛 LlmFatalException 不重试', () async {
  // 401 响应 → expectLater(call(), throwsA(isA<LlmFatalException>()))，且请求次数 == 1
});
test('429 + Retry-After:30 → 重试 3 次后抛 RecoverableExhausted', () async {});
test('网络异常(无 HTTP 码) → 指数退避 2/4/8s 重试', () async {});
test('message 含 Constraint → PipelineBlockingException', () async {});
test('CancellationException 立即传播（幻影重试防护）', () async {});
```

- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — 超时用 `Future.timeout` + `onTimeout` 返回 null（**不要**用 `catchError` 吞 Cancellation）；重试等待 sleep 用 `Future.delayed`（注入 delay 便于测试，仿 Kotlin 的 sleep 注入）；HTTP 码从 dio `DioException` 的 `response?.statusCode` 取（不靠正则）；分类器正则保留原样（"Constraint"/"disk I/O"/"HTTP (\d+)" 逻辑等价）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: LLM 客户端（dio 超时/重试/三分类）`

### Task 14: Prompt 加载 + 文章生成用例

**Files:**
- Create: `lib/domain/generation/prompt_loader.dart`、`article_prompts.dart`、`word_prompts.dart`、`lib/domain/usecase/generate_articles_use_case.dart`、`parse_article_response.dart`
- Test: `test/domain/generation/generate_articles_use_case_test.dart`

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/domain/generation/*.kt` + `usecase/GenerateArticlesUseCase.kt` + `GenerateArticlesUseCaseTest.kt`（**逐用例移植**，含 Fakes 语义）

**Interfaces:**
- Produces: `Future<GenerateResult> generateArticles(int batchId, int appVersionCode)`；`GenerateResult{finished: bool}`；`String buildArticleSystemPrompt(DifficultyLevel)`；`String buildArticleUserPrompt(ContentCategory, int orderIndex)`；`ParsedArticle{title, paragraphs: List<(en, zh)>}`；`Future<ParsedWordDetail?> parseWordLlmResponse(String)`

- [ ] **Step 1: 写失败测试** — 移植用例覆盖：
  - 全部成功 → finished=true、批次 READY、段落替换正确（删旧写新）
  - 1 篇 TIMEOUT → finished=false（不 READY）
  - 1 篇 FATAL → 批次留 GENERATING、finished=true、**永不 READY**
  - PipelineBlocking → 批次 BLOCKED + 全局 pipeline_status 阻塞 + 重抛
  - 错误落库与文章状态同事务
  - prompt 文件缺失回退内置字符串
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — XML 解析用正则/手工解析（`<title>`/`<paragraph>`/`<translation>`，与原版解析器等价）；`categoryToDifficulty` 映射表从 Kotlin 抄；prompt 从 assets 加载（`rootBundle.loadString`，失败回退常量）；`markBatchReady` 后由 Task 16 的告警钩子发完成卡片（本任务先留接口 `onBatchReady` 回调，Task 16 接飞书）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: 文章生成用例 + prompt 加载 + XML 解析`

### Task 15: 其余 Use cases

**Files:**
- Create: `lib/domain/usecase/add_word_use_case.dart`、`activate_seed_batch_use_case.dart`、`create_initial_batch_use_case.dart`、`trigger_next_batch_use_case.dart`、`get_home_articles_use_case.dart`、`resend_pending_alerts_use_case.dart`
- Test: `test/domain/usecase/`（移植 `AddWordUseCaseTest.kt`、`ResendPendingAlertsUseCaseTest.kt` 全部用例）

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/domain/usecase/` 6 文件 + 对应测试

**Interfaces:**
- Produces: `AddWordResult{addedToVocabulary, alreadyExisted}`；`AddWordUseCase(String input)` 校验规则（仅字母/空格/连字符/撇号、≤50 字符、至少一字母，错误映射为 AppError）；`TriggerNextBatchUseCase.invoke(level, dailyCount)` 决策链 4 步；`GetHomeArticlesUseCase` 过滤规则（非 PENDING + categoryToDifficulty==用户难度 + orderIndex 排序 + displayLimit 快照；不足退回全部）；`CreateInitialBatchUseCase`（建批+5 篇+立即分配今天）；`ActivateSeedBatchUseCase`（首个 READY 种子批次分配今天）；`ResendPendingAlertsUseCase`（24h 内未通知错误日志 + 未通知 READY 批次）

- [ ] **Step 1: 写失败测试** — 每个用例移植 Kotlin 测试；AddWord 校验边界（"hello world!" 拒绝、50 字符限制、大小写归一化）
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: 其余 use cases（6 个）`

---

## Phase 3：TTS

### Task 16: TTS 引擎（KittenTTS 默认 + flutter_tts 兜底）

**Files:**
- Create: `lib/data/tts/tts_engine.dart`（接口）、`kitten_tts_engine.dart`、`system_tts_engine.dart`、`tts_engine_factory.dart`、`lib/domain/tts/tts_engine.dart`（领域接口）
- Test: `test/data/tts/tts_test.dart`
- Assets: `assets/kittentts_models/`（nano-int8 模型文件）

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/data/tts/TtsEngineImpl.kt` + `domain/tts/TtsEngine.kt` + `feat/kittentts-tts-engine` 分支的 `scripts/build_kittentts.sh`（模型下载 URL）

**Interfaces:**
- Produces: `abstract class TtsEngine { Future<void> init(); bool get isReady; String? get failureMessage; String? speak(String text, double speed, {bool interrupt = true}); void stop(); Stream<String> get onSpeakingFinished; }`（utteranceId 语义保留：speak 返回 id，完成流带 id，消费方校验防串扰）；`Future<TtsEngine> createTtsEngine({required bool useKittenTts})` — KittenTTS 优先，初始化失败自动回退 SystemTts（flutter_tts：引擎链 com.xiaomi.mibrain.speech → com.google.android.tts → 默认，iOS 用默认）

- [ ] **Step 1: 模型打包** — 从 `feat/kittentts-tts-engine` 分支 `scripts/build_kittentts.sh` 提取 nano-int8 模型下载 URL，下载至 `assets/kittentts_models/`（git-lfs 或直接提交，约 25MB；确认许可 Apache 2.0）。若脚本已不存在则从 KittenTTS-flutter 仓库 README/代码中找模型清单（nano-int8 `.onnx`）
- [ ] **Step 2: 写失败测试**（引擎抽象契约，用 fake 实现）— speak 返回 id、onSpeakingFinished 事件、stop 清理；回退逻辑：createTtsEngine 在 KittenTTS init 失败时返回 SystemTts
- [ ] **Step 3: 运行确认失败**
- [ ] **Step 4: 实现 KittenTtsEngine** — `KittenTTS.create(player: AudioPlayer())`；模型从 assets 安装到应用目录（首次启动解压，marker 文件跳过，参照原 Kittentts 计划 AssetsInstaller 语义）；语速映射：UI 1x→KittenTTS speed 1.0、0.75x→0.75（真机验证听感后微调）；播放完成通过 KittenTTS 的完成回调映射 utteranceId（实现时按其 API 文档适配；若 SDK 只给"全部播完"，段落级完成用 FIFO 队列长度计数推演，真机验证）
- [ ] **Step 5: 实现 SystemTtsEngine** — flutter_tts `setEngine` 回退链（依次尝试，init 成功即保留，失败 shutdown 换下一个）；`setSpeechRate` 映射 0.70/0.45；`Locale('en')`；utteranceId 用自增计数（原版 `"ctx-$n"`）
- [ ] **Step 6: 真机验证** — KittenTTS 发音正常、语速切换、杀进程重进仍可用；断网时兜底链正常
- [ ] **Step 7: Commit** — `feat: TTS 引擎（KittenTTS 默认 + 系统兜底）`

---

## Phase 4：后台与监控

### Task 17: 飞书告警

**Files:**
- Create: `lib/monitoring/feishu_alert_sender.dart`、`lib/domain/developer_alert_sender.dart`、`lib/domain/background_work_scheduler.dart`（接口）
- Test: `test/monitoring/feishu_alert_sender_test.dart`

**参照:** `impl/app/android/app/src/main/java/com/ak/contexta/monitoring/FeishuAlertSender.kt` + `domain/DeveloperAlertSender.kt` + `ResendPendingAlertsUseCase`（Task 15 已实现）

**Interfaces:**
- Produces: `class FeishuAlertSender implements DeveloperAlertSender { Future<bool> sendErrorAlert(prefix, errorCode, batchId, message, {required AlertLevel level}); Future<bool> sendBatchReady(readyBatch); }`；`enum AlertLevel { fatal, warning, success }`；5 分钟内存去重（`Map<String, int>` 记录时间戳）；响应解析（业务 code != 0 → false）

- [ ] **Step 1: 写失败测试** — 移植语义：签名正确性（固定 secret/timestamp 断言 Base64 值）、URL 编码（`+`→`%2B` 必须）、HTTP 200 但业务 code=19021 → false、错误消息截断 500 字符、5 分钟去重、异常返回 false
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — 用 dio 或 http POST `{url}?timestamp={now-30}&sign={urlEncode(sign)}`；`crypto` 包 HMAC-SHA256；JSON 用 `dart:convert` 构造卡片（interactive + header template red/orange/green，字段对齐原版）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: 真机验证** — 用本地 webhook 或临时测试 webhook 发一条绿色卡片确认签名/送达
- [ ] **Step 6: Commit** — `feat: 飞书告警（签名/去重/业务码校验）`

### Task 18: 后台生成 worker + 调度器 + 启动恢复

**Files:**
- Create: `lib/worker/generation_scheduler.dart`、`lib/worker/article_generation_task.dart`、`lib/domain/usecase/startup_orchestration_use_case.dart`、`lib/domain/background_work_scheduler.dart`（实现）
- Test: `test/domain/usecase/startup_orchestration_use_case_test.dart`（移植 Kotlin 全部用例）
- Modify: `android/` 壳（Manifest 已配权限，Task 1）；iOS 壳（后台配置按 workmanager 插件文档，降级即可）

**参照:** `worker/` 4 文件 + `domain/usecase/StartupOrchestrationUseCase.kt` + `StartupOrchestrationUseCaseTest.kt` + 探索报告 1.3/1.4 节

**Interfaces:**
- Produces: `Future<void> scheduleBatchGeneration(int batchId)`（uniqueWork KEEP + 30s 指数退避 + tag）；`Future<void> cancelAllGeneration()`；`Future<StartupResult> startupOrchestrate(int appVersionCode)` 返回 `Ready | NeedsOnboarding | NeedsInitialBatch | PipelineBlocked`；worker 任务函数 `Future<bool> runGenerationTask(int batchId)`（true=成功/终态，false=需要 retry）

- [ ] **Step 1: 写失败测试**（StartupOrchestration）— 移植 Kotlin 用例：孤儿修复顺序、卡死批次重调度、PipelineBlocked 与版本升级解除（recoverIfNewerVersion）、NeedsInitialBatch 分支、已分配时前置生成
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现 StartupOrchestration** — 对照 Kotlin 逐步（阻塞检查→onboarding→快照→孤儿修复→重调度→补发告警(runCatching)→分配/前置生成）
- [ ] **Step 4: 实现 worker 接线** — flutter_workmanager：`Workmanager().initialize(callbackDispatcher, ...)`（Android 前台服务通知：按插件当前版本 API 配置 foreground notification，渠道 "article_generation" IMPORTANCE_LOW，标题"Contexta 正在生成文章"）；`CallbackDispatcher` 顶层函数接收 `batchId` → `runGenerationTask` → `TaskResult.success/retry/failure` 映射（原版：finished=false→retry；attempt<2→retry；PipelineBlocking→failure）；**expedited 支持按插件能力，不支持则普通 work + 启动恢复兜底**（行为差异记入验收报告）
- [ ] **Step 5: 数据库路径对齐验证** — 真机覆盖安装（不卸载旧版）→ 首页读到历史数据（Task 8 的 Step 5 正式走查）；路径不一致时在壳侧用 MethodChannel 暴露 `context.getDatabasePath()` 供 Dart 使用
- [ ] **Step 6: 真机验证** — 触发一次真实生成（断网重试/超时分类走查）、杀进程后批次继续生成、启动后孤儿修复与告警补发
- [ ] **Step 7: Commit** — `feat: 后台生成 worker + 启动恢复（workmanager）`

---

## Phase 5：UI

### Task 19: 设计 token + 组件库

**Files:**
- Create: `lib/ui/theme/app_colors.dart`、`app_type.dart`、`app_spacing.dart`、`app_radius.dart`、`app_motion.dart`、`lib/ui/components/`（12 个组件：AppButton、AppIconButton、AppBadge、AppCard、AppModal、AppToast、AppTopBar、ArticleCard、BottomNavBar、LoadingIndicator、EmptyState、StatCard、SectionLabel）
- Test: `test/ui/theme/theme_test.dart`（关键 token 值断言，防回归）

**参照:** `ui/theme/*.kt` + `ui/components/*.kt` + `docs/UI设计系统.md` + 探索报告第 3 节（完整 token 表）

- [ ] **Step 1: 写失败测试** — 断言颜色 hex、字号 sp 值与探索报告一致（如 Primary=0xFFCC785C、displayLarge=36）
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现 token** — `AppColors` 常量类（19 色 + 高亮 0x2ECC785C）；`AppType`（serif 用 `fontFamily: 'serif'`（Android）/ iOS 用 `'Times New Roman'` 平台分支，或 `fontFamilyFallback`，真机验证字形与 Android 一致；sans 用默认）；`AppSpacing/AppRadius/AppMotion`
- [ ] **Step 4: 实现组件** — 逐一对照 Kotlin 组件规格（探索报告 3.4 表格）：AppButton（Primary 珊瑚实心/Secondary/禁用 alpha 0.4）、AppModal（Center ≤360dp / BottomCenter ≤75% 高、Scrim 0x59231815、AnimatedVisibility 300ms）、ArticleCard（标题/描述两行省略/难度徽标 CET4→Coral、CET6→Green、其他 Default/已读 ✓）、BottomNavBar（4 tab、选中 Primary、1dp 分隔线、仅 home/reference/settings 显示由导航层控制）
- [ ] **Step 5: 测试通过**
- [ ] **Step 6: Commit** — `feat: UI 设计 token + 12 组件`

### Task 20: 导航框架

**Files:**
- Create: `lib/navigation/app_router.dart`、`lib/navigation/screen.dart`、`lib/app.dart`（MaterialApp + theme + router + ProviderScope）、`lib/main.dart`（改写）
- Test: `test/navigation/router_test.dart`

**参照:** `navigation/NavGraph.kt` + `MainActivity.kt` + 探索报告第 2 节导航结构

**Interfaces:**
- Produces: go_router routes：`/onboarding`（start，已 onboarding 自动重定向 /home）、`/home`、`/reading/:articleId`（全屏无底栏）、`/vocabulary`（无底栏，返回键退出）、`/add_word`、`/reference`、`/settings`；`showBottomBar` 仅 home/reference/settings；底栏切换 `launchSingleTop` 语义（go_router 默认 push 同 route 或 replace）

- [ ] **Step 1: 写失败测试** — 路由表存在性 + 重定向逻辑（未 onboarding → /onboarding；已 onboarding → /home）
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — `main.dart` 中 `Workmanager.initialize`（Task 18）+ `ProviderScope` + `MaterialApp(theme: AppTheme.light())`；onboarding 完成时 `context.go('/home')`；Reading/AddWord 返回 `context.pop()`
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: 导航框架（go_router + 底栏显示规则）`

### Task 21: Onboarding 页

**Files:**
- Create: `lib/ui/onboarding/onboarding_screen.dart`、`onboarding_controller.dart`
- Test: `test/ui/onboarding/onboarding_test.dart`

**参照:** `ui/onboarding/*.kt` + 探索报告 1.1 节

- [ ] **Step 1: 写失败测试**（controller 逻辑：步骤推进/回退、未选禁用、completeOnboarding 调仓储 + 激活种子批次）
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — 3 步流程 UI（radio-card：选中 2dp Primary 边框 + SurfaceStrong 底；22dp 圆形单选指示）、ProgressDots、底部按钮（上一步 OutlinedButton / 下一步 primary、步骤未选禁用）、确认卡（MenuBook 珊瑚图标 + 摘要）；`completeOnboarding` → settings.completeOnboarding + ActivateSeedBatchUseCase → `context.go('/home')`
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: Onboarding 页`

### Task 22: Home 页

**Files:**
- Create: `lib/ui/home/home_screen.dart`、`home_controller.dart`
- Test: `test/ui/home/home_controller_test.dart`

**参照:** `ui/home/*.kt` + 探索报告 1.2 节

- [ ] **Step 1: 写失败测试**（controller：startupOrchestrate 各分支状态、NeedsInitialBatch → 创建批次+调度生成+isGenerating、Ready → 文章流按难度过滤、streak 计算、设置变更重新观察）
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — 头部（日期「2026年8月7日 星期五」+ Streak 胶囊，streak>0 才显示）；DayGroup（今天/昨天/日期、折叠动画、ArticleCard 列表）；三态（加载/生成中 EmptyState+文案/空态）；点击文章 → `context.push('/reading/$id')`；无下拉刷新（保持原行为）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: Home 页`

### Task 23: Reading 页（一）：正文 + 分词 + 译文模式

**Files:**
- Create: `lib/ui/reading/reading_screen.dart`、`reading_controller.dart`、`lib/ui/reading/word_extractor.dart`、`translation_visibility.dart`
- Test: `test/ui/reading/reading_word_extraction_test.dart`（**移植 ReadingWordExtractionTest.kt 全部用例**）、`test/ui/reading/translation_mode_test.dart`（**移植 TranslationModeTest.kt**）

**参照:** `ui/reading/*.kt` + `ReadingWordExtractionTest.kt` + `TranslationModeTest.kt` + 探索报告 1.3 节

- [ ] **Step 1: 写失败测试** — 分词正则 `[A-Za-z]+(?:['-][A-Za-z]+)*` 全部用例（I'm、state-of-the-art、"dreams." 末尾标点、段落末尾单词）；译文模式循环 FULL→DIM→BLURRED→HIDDEN→FULL 持久化
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现正文** — 滚动进度条（3dp Primary 宽 = scrollFraction）；标题 displayMedium serif 28sp + Hairline 分隔；段落 18sp/30sp 行高；分词可点击（RichText TextSpan + 正则，点击查词回调）；生词高亮 `background: Color(0x2ECC785C)`；段落内联播放图标（18sp VolumeUp/Stop，点击 playParagraph）；译文 4 模式（DIM alpha 0.55、BLURRED blur 4dp 点击揭示 + 10s 后自动重新模糊、HIDDEN 不渲染）；「标记已读」Secondary 全宽按钮 + ✓ 已读标记
- [ ] **Step 4: 阅读计时** — 120s 计时（15s tick addReadSeconds + tryMarkReadCompleted；手动标记 forceMarkReadCompleted）；进页 recordReadingActivity
- [ ] **Step 5: 测试通过**
- [ ] **Step 6: Commit** — `feat: Reading 正文/分词/译文模式/计时`

### Task 24: Reading 页（二）：播放条 + 查词弹窗

**Files:**
- Modify: `lib/ui/reading/reading_screen.dart`、`reading_controller.dart`
- Test: `test/ui/reading/reading_controller_test.dart`（**移植 ReadingViewModelTest.kt 全部用例**）

**参照:** `ReadingViewModelTest.kt` + 探索报告 1.3 节播放/查词部分

- [ ] **Step 1: 写失败测试** — 移植用例：播放状态机（utteranceId 防串扰：旧回调不误清新状态）、语速切换（1x↔0.75x 映射）、自动朗读（autoPlayAudio）、查词时序（弹窗立即显示 isLoading → 成功回填/失败降级仅词头）、TTS 不可用（Snackbar + 拉起系统 TTS 设置）、点词打断当前朗读
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现播放条** — 底部固定（SurfaceCard h20 v12、44dp 圆形 Primary 播放/停止钮、朗读全文/正在朗读…文案、语速胶囊 1x/0.75x）
- [ ] **Step 4: 实现查词弹窗** — BottomCenter AppModal ≤75% 高：X 关闭、词头 26sp serif + 36dp 发音钮、音标 13sp 珊瑚、按词性分组（词性 labelLarge 珊瑚、英文释义 bodySmall Ink、中文 bodyMedium MutedSoft）、全宽按钮「加入生词表/从生词表移除」即时切换
- [ ] **Step 5: 测试通过**
- [ ] **Step 6: Commit** — `feat: Reading 播放条 + 查词弹窗`

### Task 25: Vocabulary 页

**Files:**
- Create: `lib/ui/vocabulary/vocabulary_screen.dart`、`vocabulary_controller.dart`
- Test: `test/ui/vocabulary/vocabulary_controller_test.dart`（**移植 VocabularyViewModelTest.kt 全部用例**）

**参照:** `ui/vocabulary/*.kt` + 探索报告 1.4 节

- [ ] **Step 1: 写失败测试** — 移植用例：加载 shuffled 生词、markCorrect 达阈值移出（newlyKnownCount+1）、未达仅计数、自动切下一词、遍历完 → 总结页、再来一轮、fling 切卡不记判定
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — 顶栏（返回 + N/M 进度 + 圆点行 + Add 图标）；单词卡（30sp serif 单词 + 15sp 音标 + 发音钮、SenseBlock 词义框：词性+中文义同排、英文释义 15sp、example 标题 + 例句对、掌握进度「已认识 N/M 次」）；fling 切卡（垂直滚动边界 + 下甩≤-500px/s→next、上甩≥500px/s→prev，onPostFling 不消费速度）；FAB ✓（56dp 珊瑚）；总结页（Celebration 图标 + 两行统计 + 再来一轮）；空态
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: Vocabulary 页`

### Task 26: Settings 页

**Files:**
- Create: `lib/ui/settings/settings_screen.dart`、`settings_controller.dart`
- Test: `test/ui/settings/settings_controller_test.dart`

**参照:** `ui/settings/*.kt` + 探索报告 1.5 节

- [ ] **Step 1: 写失败测试** — 难度确认 → updateLevel + triggerNextBatch；篇数确认 → 仅写 DB 不触发生成；阈值/译文/自动朗读直接生效；统计 2×2
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — InlineTabs 双 tab（学习设置/学习统计）；Picker 行（难度/译文模式）+ Stepper 行（篇数 1-5/阈值 1-5）+ Toggle（自动朗读）；弹窗三件套（Picker/Info/Confirm：「当前：3篇 → 调整至：5篇 此设置将在明天生效」）；统计 tab StatCard 2×2
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: Settings 页`

### Task 27: AddWord 页

**Files:**
- Create: `lib/ui/addword/add_word_screen.dart`、`add_word_controller.dart`
- Test: `test/ui/addword/add_word_controller_test.dart`

**参照:** `ui/addword/*.kt` + 探索报告 1.6 节

- [ ] **Step 1: 写失败测试** — 四结果状态（Success/AlreadyExists/InvalidInput/Failed）、阶段消息（检查本地/AI 生成）、重置清空
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — AppTopBar + 输入卡（OutlinedTextField placeholder「例如：serendipity」、按钮禁用逻辑、提示小字）+ 错误卡（重试）+ LoadingIndicator + 结果卡（状态徽标 + 单词详情卡 + 再录一个/返回生词本）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: AddWord 页`

### Task 28: Reference 页

**Files:**
- Create: `lib/ui/reference/reference_screen.dart`、`reference_controller.dart`、`grammar_data.dart`、`alphabet_data.dart`、`phonics_data.dart`
- Test: `test/ui/reference/grammar_data_test.dart`（**移植 GrammarDataTest.kt**）、`test/ui/reference/speak_text_test.dart`（**移植 SpeakTextTest.kt**：字母读字母名、音标读拟音、按钮先字母后例词）

**参照:** `ui/reference/*.kt` + 探索报告 1.7 节

- [ ] **Step 1: 写失败测试** — 26 字母 + 48 音标 8 分组 + 23 语法点 4 组静态数据完整性与 speak 文本拼接
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现** — 三 tab（字母表 4 列网格/音标 3 列分组/语法折叠组，首组默认展开）；弹窗（56sp 大字可点击发音 + 例词 + 全宽发音按钮）
- [ ] **Step 4: 测试通过**
- [ ] **Step 5: Commit** — `feat: Reference 页（字母/音标/语法静态数据）`

---

## Phase 6：验收与收尾

### Task 29: 全量真机验收

**Files:**
- Create: `impl/app/flutter/ACCEPTANCE.md`（验收清单 + 结果记录）

**参照:** 探索报告「10 条关键行为」+ UI 页面清单 + 本 spec「测试与验收」

- [ ] **Step 1: 覆盖安装** — 不卸载旧 Android 版直接 `flutter run`/installDebug → 首页显示历史数据（12 批次/60 文章/10 单词）、user_settings 保留（难度/篇数/译文模式）
- [ ] **Step 2: 核心链路** — onboarding（已 onboarding 直接跳首页）→ 阅读（分词点击/查词/译文 4 模式/播放/120s 自动已读）→ 生词本（FAB 掌握流转）→ 设置（难度确认触发新批次生成）→ 录入单词
- [ ] **Step 3: 10 条行为逐项** — LLM 超时分类、批次不卡死（未完成→retry）、孤儿修复、每天每难度一批、FATAL 永不 READY、告警送达回写、飞书签名、杀进程续跑、前台服务通知、dailyCountSnapshot 展示
- [ ] **Step 4: TTS** — KittenTTS 默认发音、语速 1x/0.75x、断模型回退系统 TTS、自动朗读
- [ ] **Step 5: 修复** — 验收发现的问题逐项修复并补测试，直至清单全绿
- [ ] **Step 6: Commit** — `docs: 真机验收报告（ACCEPTANCE.md）`

### Task 30: 删除 Android 目录 + 同步主题文档

**Files:**
- Delete: `impl/app/android/`（整个目录）
- Modify: `CLAUDE.md`（仓库结构：`impl/app/flutter`）、`impl/app/flutter/docs/ARCHITECTURE.md`、`UI设计系统.md`、`文章生成.md`、`手动录入单词.md`（从 Android 技术描述更新为 Flutter 实现：Room→drift、ViewModel→Riverpod、WorkManager→workmanager 插件、TTS 双引擎；行为/状态机/错误码部分保持不变）
- Move: `impl/app/android/app/docs/*.md` → `impl/app/flutter/docs/`（内容改写后）

**参照:** CLAUDE.md 文档驱动开发工作流（理解→实现→验证→同步文档→提交）

- [ ] **Step 1: 删除 android 目录** — `git rm -r impl/app/android`（保留 git 历史；.backup/ 不受影响）
- [ ] **Step 2: 改写 4 篇主题文档** — 分析本分支 git diff，逐篇更新受影响的章节（架构分层、DI、文章生成管道、查词系统、UI 设计系统、TTS 引擎）；Mermaid 图保留并适配新实现
- [ ] **Step 3: 更新 CLAUDE.md** — 仓库结构、入门指引（flutter run/test 命令）
- [ ] **Step 4: 检查遗留** — grep 全仓残留的 `impl/app/android` 路径引用（如本 spec/plans 文档引用可保留为历史记录）
- [ ] **Step 5: Commit** — `refactor!: 移除 Android 原生实现，切换 Flutter（docs 同步）`

### Task 31: PR 与合并

- [ ] **Step 1: 检查分支状态** — `git status` clean、`flutter analyze` 0 issue、`flutter test` 全绿
- [ ] **Step 2: 合并 main** — `git checkout main && git pull && git merge feat/flutter-migration`（保留 Android 历史在 git 中）
- [ ] **Step 3: Push + PR** — `git push origin feat/flutter-migration` + `gh pr create`（标题：Android→Flutter 迁移；body 引用 spec/plan/ACCEPTANCE 结论，结尾加 `🤖 Generated with [Claude Code](https://claude.com/claude-code)`）
- [ ] **Step 4: 验证** — CI/本地重新跑全量测试

---

## Self-Review 结果

**1. Spec 覆盖对照**（spec 每节 → 任务）：
- 技术栈对照表 → Task 1（脚手架/依赖/assets）、Task 12（DI）、Task 13（LLM dio）
- 数据库兼容方案（打开流程/逐列复刻/种子/验收）→ Task 4-8（表组三连 + 打开策略 + 旧库验证）
- TTS 方案（默认+兜底/模型打包/语速映射/防串扰）→ Task 16（模型打包 Step 1、回退链 Step 5、语速 Step 4）
- 后台生成（workmanager/启动恢复/retry 语义）→ Task 18；启动恢复细节（孤儿修复/补发）→ Task 18 Step 1-3
- 领域逻辑 10 条：1-2→Task 13/18；3→Task 10；4-5→Task 15；6-8→Task 14/17；9→Task 18；10→Task 15（GetHomeArticles）
- UI 复刻要点（7 页/设计系统/导航 quirk/静态数据）→ Task 19-28（导航 quirk：vocabulary 无底栏 → Task 20 Step 3）
- 错误处理与监控（错误体系/分类/告警细节）→ Task 3、13、17
- 测试与验收（10 条行为清单 + 页面走查 + 数据库验证）→ 各任务 TDD + Task 8 + Task 29
- 执行计划 10 步 → Task 1 起对应；"删除 Android + 文档同步"→ Task 30；PR → Task 31
- 风险表 → 已内嵌各任务（Task 7 路径、Task 16 KittenTTS API、Task 18 expedited）

**2. 占位符扫描**：无 TBD/TODO；两处"按插件当前文档/API"（Task 16 KittenTTS 播放回调、Task 18 workmanager foreground）是外部依赖不确定项，已标注真机验证补救路径，非占位符。

**3. 类型一致性**：
- `buildAppDatabase({String? overridePath})` / `writeSeedIfNeeded`（Task 7）→ Task 8 使用 ✓
- `AppDatabase.forTesting(QueryExecutor)`（Task 4 补定义）→ Task 4/7/8 测试使用 ✓
- `TtsEngine{speak→utteranceId, onSpeakingFinished 流, stop}`（Task 16）→ Task 24 防串扰消费 ✓
- `GenerateResult{finished}`（Task 14）→ Task 18 `runGenerationTask→bool` 映射 ✓
- `ResendPendingAlertsUseCase`（Task 15）→ Task 18 启动编排调用 ✓
- `BackgroundWorkScheduler` 接口（Task 17）→ Task 18 实现 ✓
- 表类名（ArticleBatches/Articles/...）贯穿 Task 4-12，`db.<表名>` 引用一致 ✓
- `isoOffsetDateTime`/`isoLocalDate`/`nowMillis`（Task 1）→ 全仓统一使用 ✓
