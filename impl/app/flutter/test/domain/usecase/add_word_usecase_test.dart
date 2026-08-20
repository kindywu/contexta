import 'package:contexta/data/remote/llm_api.dart';
import 'package:contexta/data/remote/server_api_client.dart';
import 'package:contexta/domain/error/llm_exceptions.dart';
import 'package:contexta/domain/error/pipeline_blocking_exception.dart';
import 'package:contexta/domain/model/daily_stats.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/model/word_detail.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/repository/word_repository.dart';
import 'package:contexta/domain/usecase/add_word_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// 对照 Kotlin AddWordUseCaseTest.kt 移植（12 个用例）。

class FakeWordRepository implements WordRepository {
  WordDetail? findLocalResult;
  Object? saveError;
  WordDetail? saveResult;
  final List<String> savedCalls = [];
  int findLocalCalls = 0;

  @override
  Future<WordDetail?> findLocal(String spelling) async {
    findLocalCalls++;
    return findLocalResult;
  }

  @override
  Future<WordDetail> saveLlmResult(
    String spellingDisplay,
    String? phoneticIpa,
    List<WordSense> senses, {
    String? normalized,
  }) async {
    savedCalls.add(normalized ?? spellingDisplay);
    final e = saveError;
    if (e != null) throw e;
    return saveResult!;
  }

  @override
  Future<WordDetail?> lookupWord(
          String spelling, Future<WordDetail?> Function(String) llmFallback) =>
      throw UnimplementedError();

  @override
  Future<WordDetail?> getWordDetail(int wordId) => throw UnimplementedError();

  @override
  Future<Map<int, WordDetail>> getWordDetails(List<int> wordIds) =>
      throw UnimplementedError();

  @override
  Future<void> invalidateCache(String spelling) => throw UnimplementedError();
}

class FakeVocabularyRepository implements VocabularyRepository {
  int? addWordResult;
  int addWordCalls = 0;

  @override
  Future<int?> addWord(int wordId) async {
    addWordCalls++;
    return addWordResult;
  }

  @override
  Stream<List<VocabWord>> observeActive() => throw UnimplementedError();

  @override
  Future<int> getActiveCount() => throw UnimplementedError();

  @override
  Future<List<VocabWord>> getActiveWords() => throw UnimplementedError();

  @override
  Future<void> markCorrect(int entryId, {int masteryThreshold = 1}) =>
      throw UnimplementedError();

  @override
  Future<void> markIncorrect(int entryId) => throw UnimplementedError();

  @override
  Future<void> removeWord(int entryId, {String reason = 'MANUAL_REMOVAL'}) =>
      throw UnimplementedError();

  @override
  Future<int> countDistinctWords() => throw UnimplementedError();
}

class FakeStatsRepository implements StatsRepository {
  int recordWordAddedCalls = 0;

  @override
  Future<void> recordWordAdded() async {
    recordWordAddedCalls++;
  }

  @override
  Stream<DailyStats?> observeStats() => throw UnimplementedError();

  @override
  Future<DailyStats?> getStats() => throw UnimplementedError();

  @override
  Future<void> recordReadingActivity({int secondsSpent = 0}) =>
      throw UnimplementedError();
}

class FakeLlmApi implements LlmApi {
  Object? throwError;
  WordDetail result = _sampleDetail(42);
  int callCount = 0;
  String? lastWord;

  @override
  Future<WordDetail> wordLookup(String word) async {
    callCount++;
    lastWord = word;
    final e = throwError;
    if (e != null) throw e;
    return result;
  }
}

WordDetail _sampleDetail(int wordId, {bool isInVocabulary = false}) {
  final sense = WordSense(
    id: 1,
    orderIndex: 1,
    partOfSpeech: 'n.',
    chineseMeaning: '意外发现珍奇事物的运气',
    englishDefinition:
        'The occurrence and development of events by chance in a happy or beneficial way.',
    examples: [
      ExampleSentence(
        id: 1,
        orderIndex: 1,
        sentenceEn: 'It was pure serendipity that we met.',
        sentenceZh: '我们的相遇纯属幸运。',
        isPrimary: true,
      ),
    ],
  );
  return WordDetail(
    wordId: wordId,
    spellingDisplay: 'Serendipity',
    phoneticIpa: '/ˌserənˈdɪpəti/',
    primarySense: sense,
    allSenses: [sense],
    isInVocabulary: isInVocabulary,
    vocabularyEntryId: isInVocabulary ? 7 : null,
  );
}

void main() {
  late FakeWordRepository words;
  late FakeVocabularyRepository vocab;
  late FakeStatsRepository stats;
  late FakeLlmApi llm;
  late AddWordUseCase useCase;

  setUp(() {
    words = FakeWordRepository();
    vocab = FakeVocabularyRepository();
    stats = FakeStatsRepository();
    llm = FakeLlmApi();
    useCase = AddWordUseCase(
      wordRepository: words,
      vocabularyRepository: vocab,
      statsRepository: stats,
      llmApi: llm,
    );
  });

  // ─── 校验 ───────────────────────────────────────────────

  test('空白输入被拒绝', () async {
    final result = await useCase('   ');
    expect(result, isA<AddWordResultInvalidInput>());
    expect((result as AddWordResultInvalidInput).message, contains('请输入'));
  });

  test('非字母输入被拒绝', () async {
    expect(await useCase('1234'), isA<AddWordResultInvalidInput>());
    expect(await useCase('你好'), isA<AddWordResultInvalidInput>());
  });

  test('超过最大长度被拒绝', () {
    final long = 'a' * (AddWordUseCase.maxInputLength + 1);
    final error = AddWordUseCase.validate(long);
    expect(error, isNotNull);
    expect(error, contains('过长'));
  });

  test('合法单词通过校验', () {
    expect(AddWordUseCase.validate('serendipity'), isNull);
    expect(AddWordUseCase.validate('ice cream'), isNull);
    expect(AddWordUseCase.validate("can't"), isNull);
  });

  test('无效输入不触发 LLM 与本地查询', () async {
    await useCase('你好');
    expect(llm.callCount, 0);
    expect(words.findLocalCalls, 0);
  });

  // ─── 本地命中 ───────────────────────────────────────────

  test('词库已存在且不在生词库时 加入生词库并返回 AlreadyExists', () async {
    words.findLocalResult = _sampleDetail(1);
    vocab.addWordResult = 1;

    final result = await useCase('Serendipity');

    expect(result, isA<AddWordResultAlreadyExists>());
    final already = result as AddWordResultAlreadyExists;
    expect(already.detail.wordId, 1);
    expect(already.addedToVocabulary, isTrue);
    expect(llm.callCount, 0);
    expect(vocab.addWordCalls, 1);
    expect(stats.recordWordAddedCalls, 1);
  });

  test('词库已存在且已在生词库时 不重复加入', () async {
    words.findLocalResult = _sampleDetail(1, isInVocabulary: true);

    final result = await useCase('serendipity');

    expect(result, isA<AddWordResultAlreadyExists>());
    expect((result as AddWordResultAlreadyExists).addedToVocabulary, isFalse);
    expect(vocab.addWordCalls, 0);
    expect(stats.recordWordAddedCalls, 0);
    expect(llm.callCount, 0);
  });

  // ─── LLM 生成 ───────────────────────────────────────────

  test('本地未命中时由服务端查词生成 落库并加入生词库', () async {
    words.findLocalResult = null;
    words.saveResult = _sampleDetail(42);
    vocab.addWordResult = 42;

    final stages = <AddWordStage>[];
    final result = await useCase('serendipity', onStage: stages.add);

    expect(result, isA<AddWordResultSuccess>());
    final success = result as AddWordResultSuccess;
    expect(success.detail.wordId, 42);
    expect(success.addedToVocabulary, isTrue);
    expect(stages, [AddWordStage.checkingLocal, AddWordStage.generating]);
    expect(llm.lastWord, 'serendipity');
    expect(words.savedCalls, ['serendipity']);
    expect(vocab.addWordCalls, 1);
    expect(stats.recordWordAddedCalls, 1);
  });

  test('查词响应无有效义项（解析失败）时 返回拼写提示', () async {
    words.findLocalResult = null;
    llm.throwError = const FormatException('word-lookup 返回空义项');

    final result = await useCase('serendipity');

    expect(result, isA<AddWordResultFailed>());
    expect((result as AddWordResultFailed).message, contains('拼写'));
    expect(vocab.addWordCalls, 0);
    expect(stats.recordWordAddedCalls, 0);
  });

  test('ServerApiException（LLM_FATAL）经统一映射走既有分类分支', () async {
    words.findLocalResult = null;
    llm.throwError = const ServerApiException(
      errorCode: 'LLM_FATAL',
      message: 'fatal',
      statusCode: 500,
    );

    final result = await useCase('serendipity');

    expect(result, isA<AddWordResultFailed>());
    expect((result as AddWordResultFailed).message, contains('AI 服务暂不可用'));
  });

  test('查词配额用尽 → 配额专用提示（非通用失败文案）', () async {
    words.findLocalResult = null;
    llm.throwError = const ServerApiException(
      errorCode: 'QUOTA_EXCEEDED',
      message: 'quota',
      statusCode: 429,
    );

    final result = await useCase('serendipity');

    expect(result, isA<AddWordResultFailed>());
    expect((result as AddWordResultFailed).message, '今日查词次数已用完');
    expect(vocab.addWordCalls, 0);
    expect(stats.recordWordAddedCalls, 0);
  });

  test('LlmFatalException 映射为 AI 服务不可用', () async {
    words.findLocalResult = null;
    llm.throwError = LlmFatalException('auth failed');

    final result = await useCase('serendipity');

    expect(result, isA<AddWordResultFailed>());
    expect((result as AddWordResultFailed).message, contains('AI 服务暂不可用'));
  });

  test('LlmRecoverableExhaustedException 映射为网络不稳定', () async {
    words.findLocalResult = null;
    llm.throwError = LlmRecoverableExhaustedException('timeout', attempts: 3);

    final result = await useCase('serendipity');

    expect(result, isA<AddWordResultFailed>());
    expect((result as AddWordResultFailed).message, contains('网络不稳定'));
  });

  test('PipelineBlockingException 映射为系统暂时无法生成', () async {
    words.findLocalResult = null;
    llm.throwError = PipelineBlockingException('DB constraint violated');

    final result = await useCase('serendipity');

    expect(result, isA<AddWordResultFailed>());
    expect((result as AddWordResultFailed).message, contains('系统暂时无法生成'));
  });

  test('未知异常映射为通用失败', () async {
    words.findLocalResult = null;
    llm.throwError = StateError('boom');

    final result = await useCase('serendipity');

    expect(result, isA<AddWordResultFailed>());
    expect((result as AddWordResultFailed).message, contains('录入失败'));
  });
}
