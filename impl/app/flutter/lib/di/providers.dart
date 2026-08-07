import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/time/iso8601.dart';
import '../data/local/database_open.dart';
import '../data/local/daos/article_daos.dart';
import '../data/local/daos/settings_daos.dart';
import '../data/local/daos/word_daos.dart';
import '../data/repository/article_repository_impl.dart';
import '../data/repository/settings_repository_impl.dart';
import '../data/repository/stats_repository_impl.dart';
import '../data/repository/vocabulary_repository_impl.dart';
import '../data/repository/word_repository_impl.dart';
import '../domain/repository/article_repository.dart';
import '../domain/repository/settings_repository.dart';
import '../domain/repository/stats_repository.dart';
import '../domain/repository/vocabulary_repository.dart';
import '../domain/repository/word_repository.dart';
import '../data/local/database.dart';

/// 数据库（生产路径：打开时 onCreate 建表 + 种子写入）。
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await buildAppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 时间注入：ISO 偏移日期时间（与 Kotlin TimeProvider.nowDateTimeString 对齐）。
final nowIsoProvider = Provider<String Function()>((ref) => () => isoOffsetDateTime(DateTime.now()));

/// 日期注入：yyyy-MM-dd（与 Kotlin Converter.currentDateString 对齐）。
final todayProvider = Provider<String Function()>((ref) => () => isoLocalDate(DateTime.now()));

/// 词库仓储（LRU(50) + Semaphore(3)，单例：缓存与并发限制跨调用共享）。
final wordRepositoryProvider = Provider<WordRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return WordRepositoryImpl(
    WordDao(db),
    WordSenseDao(db),
    ExampleSentenceDao(db),
    VocabularyEntryDao(db),
  );
});

final articleRepositoryProvider = Provider<ArticleRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return ArticleRepositoryImpl(
    db,
    ArticleBatchDao(db),
    ArticleDao(db),
    ArticleParagraphDao(db),
    GenerationPipelineStatusDao(db),
    GenerationErrorLogDao(db),
    DailyLearningDao(db),
    ref.watch(nowIsoProvider),
    ref.watch(todayProvider),
  );
});

final vocabularyRepositoryProvider = Provider<VocabularyRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return VocabularyRepositoryImpl(
    VocabularyEntryDao(db),
    ref.watch(wordRepositoryProvider),
    ref.watch(nowIsoProvider),
  );
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return SettingsRepositoryImpl(UserSettingsDao(db));
});

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return StatsRepositoryImpl(
    DailyLearningLogDao(db),
    LearningStatsSummaryDao(db),
    ref.watch(vocabularyRepositoryProvider),
    ref.watch(todayProvider),
  );
});
