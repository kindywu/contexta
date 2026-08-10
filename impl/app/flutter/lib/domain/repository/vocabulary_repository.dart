import '../model/vocab_word.dart';

/// 生词本仓储接口（对齐 Kotlin VocabularyRepository.kt）。
abstract interface class VocabularyRepository {
  /// 观察活跃（未删除、未 MASTERED）生词条目。
  Stream<List<VocabWord>> observeActive();

  /// 活跃条目数。
  Future<int> getActiveCount();

  /// 一次性读取全部活跃生词。
  Future<List<VocabWord>> getActiveWords();

  /// 将词加入生词本（新建条目）。
  /// 返回新条目 id；已在生词本中返回 null。
  Future<int?> addWord(int wordId);

  /// 标记认识：streak+1，达到 [masteryThreshold] 自动 MASTERED。
  Future<void> markCorrect(int entryId, {int masteryThreshold = 1});

  /// 标记不认识：重置 streak。
  Future<void> markIncorrect(int entryId);

  /// 从生词本移除（软删除，记录原因）。
  Future<void> removeWord(int entryId, {String reason = 'MANUAL_REMOVAL'});

  /// 统计加入过生词本的不同词数（未删除）。
  Future<int> countDistinctWords();
}
