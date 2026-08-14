import '../../data/remote/llm_api.dart';
import '../../data/remote/server_api_client.dart';
import '../error/llm_exceptions.dart';
import '../error/pipeline_blocking_exception.dart';
import '../model/word_detail.dart';
import '../repository/stats_repository.dart';
import '../repository/vocabulary_repository.dart';
import '../repository/word_repository.dart';

/// 录入过程所处阶段，供 UI 展示进度文案（对照 Kotlin AddWordUseCase.Stage）。
enum AddWordStage { checkingLocal, generating }

/// 录入结果（对照 Kotlin AddWordUseCase.AddWordResult）。
sealed class AddWordResult {
  const AddWordResult();
}

/// 词库中原本不存在，LLM 生成并加入生词库成功。
final class AddWordResultSuccess extends AddWordResult {
  const AddWordResultSuccess({
    required this.detail,
    required this.addedToVocabulary,
  });
  final WordDetail detail;
  final bool addedToVocabulary;
}

/// 词库中已存在（本地命中，未调 LLM）。
final class AddWordResultAlreadyExists extends AddWordResult {
  const AddWordResultAlreadyExists({
    required this.detail,
    required this.addedToVocabulary,
  });
  final WordDetail detail;
  final bool addedToVocabulary;
}

final class AddWordResultInvalidInput extends AddWordResult {
  const AddWordResultInvalidInput({required this.message});
  final String message;
}

final class AddWordResultFailed extends AddWordResult {
  const AddWordResultFailed({required this.message});
  final String message;
}

/// 手动录入单词：用户输入英文单词，加入词库（word 表）和生词库
/// （vocabulary_entry 表）（对照 Kotlin AddWordUseCase.kt）。
///
/// 本地没有词典，因此词库中不存在的单词经服务端查词接口
/// （[LlmApi.wordLookup]）获取音标、释义与例句。
///
/// **流程：**
/// 1. 归一化 + 校验输入（仅英文字母/空格/连字符/撇号，长度上限）
/// 2. 本地词库检查（LRU 缓存 + Room，不触发远程调用）——[WordRepository.findLocal]
///    - 命中：直接复用已有释义；若该词不在生词库则加入（[VocabularyRepository.addWord]）
///    - 未命中：进入第 3 步
/// 3. 服务端查词 → [WordRepository.saveLlmResult] 写入词库 →
///    [VocabularyRepository.addWord] 加入生词库
/// 4. 无论命中与否，成功加入生词库时记录统计（[StatsRepository.recordWordAdded]）
///
/// **错误处理**（服务端 error_code 经 [mapErrorCodeToException] 统一映射，
/// 保留既有分类语义）：
/// - [LlmFatalException] → 服务级不可恢复（鉴权/内容策略）
/// - [LlmRecoverableExhaustedException] → 网络等可恢复错误耗尽重试
/// - [PipelineBlockingException] → 结构性错误
/// - 服务端响应无有效释义（解析失败）→ 提示检查拼写
class AddWordUseCase {
  AddWordUseCase({
    required this._wordRepository,
    required this._vocabularyRepository,
    required this._statsRepository,
    required this._llmApi,
  });

  final WordRepository _wordRepository;
  final VocabularyRepository _vocabularyRepository;
  final StatsRepository _statsRepository;
  final LlmApi _llmApi;

  Future<AddWordResult> call(
    String rawInput, {
    void Function(AddWordStage stage)? onStage,
  }) async {
    final normalized = WordRepository.normalize(rawInput);
    final invalid = validate(normalized);
    if (invalid != null) {
      return AddWordResultInvalidInput(message: invalid);
    }

    // 1. 本地词库检查：命中则不调 LLM
    onStage?.call(AddWordStage.checkingLocal);
    final existing = await _wordRepository.findLocal(normalized);
    if (existing != null) {
      final added = existing.isInVocabulary
          ? false
          : await _addToVocabulary(existing.wordId);
      return AddWordResultAlreadyExists(
        detail: existing,
        addedToVocabulary: added,
      );
    }

    // 2. 服务端查词生成
    onStage?.call(AddWordStage.generating);
    try {
      final detail = await _lookup(normalized);
      final saved = await _wordRepository.saveLlmResult(
        detail.spellingDisplay,
        detail.phoneticIpa,
        detail.allSenses,
        normalized: normalized,
      );
      final added = await _addToVocabulary(saved.wordId);
      return AddWordResultSuccess(detail: saved, addedToVocabulary: added);
    } on FormatException {
      // 服务端响应无有效义项（解析失败）→ 提示检查拼写
      return const AddWordResultFailed(
          message: 'AI 未能识别该单词的释义，请检查拼写后重试');
    } on LlmFatalException catch (e) {
      return AddWordResultFailed(message: 'AI 服务暂不可用（${e.message}），请稍后重试');
    } on LlmRecoverableExhaustedException {
      return const AddWordResultFailed(
          message: '网络不稳定，AI 多次重试后仍未成功，请稍后重试');
    } on PipelineBlockingException {
      return const AddWordResultFailed(message: '系统暂时无法生成单词信息，请稍后重试');
    } catch (_) {
      return const AddWordResultFailed(message: '录入失败，请稍后重试');
    }
  }

  /// 服务端查词：ServerApiException → [mapErrorCodeToException] 映射为既有
  /// 异常分类（LlmFatal / LlmRecoverableExhausted / LlmTimeout /
  /// PipelineBlocking / QuotaExceeded），由 call() 既有 catch 分支处理。
  Future<WordDetail> _lookup(String word) async {
    try {
      return await _llmApi.wordLookup(word);
    } on ServerApiException catch (e) {
      throw mapErrorCodeToException(e);
    }
  }

  /// 加入生词库并记录统计，返回是否新增（false = 已在生词库）。
  Future<bool> _addToVocabulary(int wordId) async {
    final entryId = await _vocabularyRepository.addWord(wordId);
    if (entryId != null) await _statsRepository.recordWordAdded();
    return entryId != null;
  }

  static final RegExp _wordPattern = RegExp(r"^[A-Za-z][A-Za-z'\- ]*$");
  static const int maxInputLength = 50;

  /// 返回 null 表示校验通过；否则返回用户可读的失败原因。
  static String? validate(String normalized) {
    if (normalized.trim().isEmpty) return '请输入要录入的单词';
    if (normalized.length > maxInputLength) {
      return '单词过长（最多 $maxInputLength 个字符）';
    }
    if (!_wordPattern.hasMatch(normalized)) {
      return '只能输入英文字母、空格、连字符和撇号';
    }
    if (!normalized.contains(RegExp('[a-zA-Z]'))) return '至少包含一个英文字母';
    return null;
  }
}
