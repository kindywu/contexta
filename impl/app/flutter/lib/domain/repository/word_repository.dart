import '../model/word_detail.dart';

/// 词库仓储接口（对齐 Kotlin WordRepository.kt + companion normalize）。
abstract interface class WordRepository {
  /// 三层查词：LRU 缓存 → 本地 DB → [llmFallback] 并落库回填。
  /// LLM 失败（返回 null）时不落库、不缓存。
  Future<WordDetail?> lookupWord(
      String spelling, Future<WordDetail?> Function(String) llmFallback);

  /// 将 LLM 结果持久化到 DB（word + senses + examples），返回完整详情。
  Future<WordDetail> saveLlmResult(
    String spellingDisplay,
    String? phoneticIpa,
    List<WordSense> senses, {
    String? normalized,
  });

  /// 仅本地查询（LRU → DB），不触发 LLM。
  Future<WordDetail?> findLocal(String spelling);

  /// 按 wordId 获取完整详情（词库复习用）。
  Future<WordDetail?> getWordDetail(int wordId);

  /// 批量获取详情，按 wordId 索引。
  Future<Map<int, WordDetail>> getWordDetails(List<int> wordIds);

  /// 使缓存失效，下次查询重新读 DB。
  Future<void> invalidateCache(String spelling);

  /// 归一化：trim + lowercase + 去除首尾标点（与 Kotlin 一致）。
  static String normalize(String spelling) {
    var s = spelling.trim().toLowerCase();
    s = s.replaceFirst(RegExp('[.,!?;:"\')]+\$'), '');
    s = s.replaceFirst(RegExp('^["\'(\\[]+'), '');
    return s;
  }
}
