import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/article_daos.dart';
import 'package:contexta/data/local/daos/settings_daos.dart';
import 'package:contexta/data/local/daos/word_daos.dart';
import 'package:contexta/data/repository/article_repository_impl.dart';
import 'package:contexta/data/repository/settings_repository_impl.dart';
import 'package:contexta/data/repository/stats_repository_impl.dart';
import 'package:contexta/data/repository/vocabulary_repository_impl.dart';
import 'package:contexta/data/repository/word_repository_impl.dart';
import 'package:contexta/domain/inflection/inflection_resolver.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/model/word_detail.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/repository/word_repository.dart';

/// Task 12 仓储层测试（对照 Android 原版 5 个 RepositoryImpl + WordRepositoryTest）。
///
/// 覆盖：
/// - WordRepository 3-tier 查词（LRU(50) → DB → LLM fallback → 落库回填）
/// - ArticleRepository 全部方法与观察流（drift watch）
/// - VocabularyRepository 生词本增删与观察流
/// - SettingsRepository 设置读写与观察流
/// - StatsRepository 统计重算与观察流
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late WordRepository wordRepo;
  late VocabularyRepository vocabRepo;
  late ArticleRepository articleRepo;
  late SettingsRepository settingsRepo;
  late StatsRepository statsRepo;

  /// 固定时间：2026-08-07 10:30:00 +08:00
  final fixedDateTime = DateTime(2026, 8, 7, 10, 30, 0);

  late DateTime now;
  String nowIso() {
    final t = now;
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}T${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}'
        '+08:00';
  }

  String nowDate() =>
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = fixedDateTime;
    wordRepo = WordRepositoryImpl(
      WordDao(db),
      WordSenseDao(db),
      ExampleSentenceDao(db),
      VocabularyEntryDao(db),
    );
    vocabRepo = VocabularyRepositoryImpl(
      VocabularyEntryDao(db),
      wordRepo,
      nowIso,
    );
    articleRepo = ArticleRepositoryImpl(
      db,
      ArticleBatchDao(db),
      ArticleDao(db),
      ArticleParagraphDao(db),
      GenerationPipelineStatusDao(db),
      GenerationErrorLogDao(db),
      DailyLearningDao(db),
      nowIso,
      nowDate,
    );
    settingsRepo = SettingsRepositoryImpl(UserSettingsDao(db));
    statsRepo = StatsRepositoryImpl(
      DailyLearningLogDao(db),
      LearningStatsSummaryDao(db),
      vocabRepo,
      nowDate,
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 手动构造 WordDetail（模拟 LLM 返回）。
  WordDetail llmDetail(String spelling,
      {List<WordSense> senses = const []}) {
    return WordDetail(
      wordId: -1,
      spellingDisplay: spelling,
      phoneticIpa: '/${spelling.toLowerCase()}/',
      primarySense: senses.isNotEmpty ? senses.first : null,
      allSenses: senses,
    );
  }

  WordSense sense(int order, {String zh = '释义', String en = 'definition'}) =>
      WordSense(
        id: -1,
        orderIndex: order,
        partOfSpeech: 'n.',
        chineseMeaning: zh,
        englishDefinition: en,
        examples: const [],
      );

  group('WordRepository 3-tier 查词', () {
    test('LRU 命中不落库、不调 LLM', () async {
      // 先落库（模拟调用方 saveLlmResult），再验证三层语义
      await wordRepo.saveLlmResult('Hello!', '/hello/', const [], normalized: 'hello!');
      var llmCalls = 0;
      final detail = await wordRepo.lookupWord('Hello!', (s) async {
        llmCalls++;
        return llmDetail(s);
      });
      expect(detail, isNotNull);
      expect(detail!.spellingDisplay, 'Hello!');
      expect(llmCalls, 1);

      // 第二次：LRU 命中
      final cached = await wordRepo.lookupWord('hello!', (s) async {
        llmCalls++;
        return llmDetail(s);
      });
      expect(cached, same(detail));
      expect(llmCalls, 1);
      expect((await db.select(db.words).get()).length, 1);
    });

    test('LRU 未命中 → 读 DB（先落库的词）', () async {
      // 模拟真实调用模式：llmFallback 内部 saveLlmResult 落库
      await wordRepo.lookupWord('apple', (s) async {
        await wordRepo.saveLlmResult('apple', null, [sense(0)], normalized: 'apple');
        return await wordRepo.findLocal('apple');
      });
      expect((await db.select(db.words).get()).length, 1);

      // 换一个新实例（LRU 清空），应命中 DB 而非 LLM
      final fresh = WordRepositoryImpl(
        WordDao(db),
        WordSenseDao(db),
        ExampleSentenceDao(db),
        VocabularyEntryDao(db),
      );
      var llmCalls = 0;
      final detail = await fresh.lookupWord('apple', (s) async {
        llmCalls++;
        return llmDetail(s);
      });
      expect(detail, isNotNull);
      expect(detail!.spellingDisplay, 'apple');
      expect(llmCalls, 0);
    });

    test('LLM 返回 null（失败）→ 返回 null 不落库', () async {
      final detail = await wordRepo.lookupWord('zzz', (s) async => null);
      expect(detail, isNull);
      expect((await db.select(db.words).get()).length, 0);
      // 再次查询仍然走 LLM（失败结果不缓存）
      var calls = 0;
      await wordRepo.lookupWord('zzz', (s) async {
        calls++;
        return null;
      });
      expect(calls, 1);
    });

    test('LLM 结果落库：word + sense + example，且可再查', () async {
      final detail = await wordRepo.lookupWord('run', (s) async {
        await wordRepo.saveLlmResult(
          'run',
          '/rʌn/',
          [WordSense(
            id: -1,
            orderIndex: 0,
            partOfSpeech: 'v.',
            chineseMeaning: '奔跑',
            englishDefinition: 'to move fast',
            examples: const [
              ExampleSentence(
                  id: -1, orderIndex: 0, sentenceEn: 'I run.', sentenceZh: '我跑。', isPrimary: true),
            ],
          )],
          normalized: 'run',
        );
        return await wordRepo.findLocal('run');
      });
      expect(detail!.wordId, greaterThan(0));

      final rows = await db.select(db.words).get();
      expect(rows.length, 1);
      final sensesRows = await db.select(db.wordSenses).get();
      expect(sensesRows.length, 1);
      expect(sensesRows.first.chineseMeaning, '奔跑');
      final exRows = await db.select(db.exampleSentences).get();
      expect(exRows.length, 1);
      expect(exRows.first.sentenceEn, 'I run.');

      // 新实例从 DB 读回完整详情
      final fresh = WordRepositoryImpl(
        WordDao(db),
        WordSenseDao(db),
        ExampleSentenceDao(db),
        VocabularyEntryDao(db),
      );
      final reloaded = await fresh.findLocal('run');
      expect(reloaded, isNotNull);
      expect(reloaded!.allSenses.length, 1);
      expect(reloaded.allSenses.first.examples.length, 1);
      expect(reloaded.isInVocabulary, false);
      expect(reloaded.vocabularyEntryId, isNull);
    });

    test('saveLlmResult：sense orderIndex<=0 时用序号', () async {
      await wordRepo.saveLlmResult(
        'go',
        '/ɡoʊ/',
        [sense(0), sense(-1, zh: '第二义')],
        normalized: 'go',
      );
      final rows = await db.select(db.wordSenses).get();
      expect(rows.map((r) => r.orderIndex), [0, 1]);
    });

    test('saveLlmResult 重复 normalized：复用已有 word id', () async {
      await wordRepo.saveLlmResult(
          'light', '/laɪt/', [sense(0)], normalized: 'light');
      await wordRepo.saveLlmResult(
          'light', null, [sense(0, zh: '新义')], normalized: 'light');
      expect((await db.select(db.words).get()).length, 1);
      final senses = await db.select(db.wordSenses).get();
      expect(senses.length, 2);
    });

    test('LRU 上限 50：超过后最旧条目被逐出', () async {
      final repo = WordRepositoryImpl(
        WordDao(db),
        WordSenseDao(db),
        ExampleSentenceDao(db),
        VocabularyEntryDao(db),
      );
      for (var i = 0; i < 55; i++) {
        // 仅填缓存（不落库）：saveLlmResult 也会写缓存，会干扰 eviction 验证
        await repo.lookupWord('w$i', (s) async => llmDetail(s));
      }
      // 前 5 个已被逐出（LRU 50）→ 再次查询走 LLM
      var calls = 0;
      await repo.lookupWord('w0', (s) async {
        calls++;
        return llmDetail(s);
      });
      expect(calls, 1);
      // 最近使用的仍在缓存
      await repo.lookupWord('w54', (s) async {
        calls++;
        return llmDetail(s);
      });
      expect(calls, 1);
    });

    test('信号量并发限制 3', () async {
      var concurrent = 0;
      var peak = 0;
      final gate = Completer<void>();
      final results = List.generate(5, (i) {
        return wordRepo.lookupWord('w$i', (s) async {
          concurrent++;
          peak = concurrent > peak ? concurrent : peak;
          await gate.future;
          concurrent--;
          return llmDetail(s);
        });
      });
      // 等 3 个持有 permit 的任务全部进入 gate 后，再放行
      while (peak < 3) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
      gate.complete();
      final done = await Future.wait(results);
      expect(peak, 3);
      expect(done.whereType<WordDetail>().length, 5);
    });

    test('invalidateCache：清除后重新查 DB', () async {
      // 先落库（模拟调用方 saveLlmResult）
      await wordRepo.saveLlmResult('apple', null, [sense(0)], normalized: 'apple');
      await wordRepo.lookupWord('apple', (s) async => llmDetail(s)); // 缓存
      wordRepo.invalidateCache('apple');
      var llmCalls = 0;
      final detail = await wordRepo.lookupWord('apple', (s) async {
        llmCalls++;
        return llmDetail(s);
      });
      expect(detail, isNotNull);
      expect(llmCalls, 0); // DB 命中，不调 LLM
    });

    test('getWordDetail / getWordDetails', () async {
      final saved = await wordRepo.saveLlmResult(
          'cat', '/kæt/', [sense(0)], normalized: 'cat');
      expect((await wordRepo.getWordDetail(saved.wordId))!.spellingDisplay, 'cat');
      expect((await wordRepo.getWordDetail(999)), isNull);

      final map = await wordRepo.getWordDetails([saved.wordId, 999]);
      expect(map.length, 1);
      expect(map[saved.wordId]!.phoneticIpa, '/kæt/');
    });
  });

  group('WordRepository 词形解析（inflection resolution）', () {
    test('homes 精确 miss 时解析命中 home，不触发 LLM', () async {
      // 预置 home 词条（saveLlmResult 返回 WordDetail）
      await wordRepo.saveLlmResult(
        'home', '/hoʊm/', const [
          WordSense(id: 0, orderIndex: 1, partOfSpeech: 'n.',
              chineseMeaning: '家', englishDefinition: 'a place where you live',
              examples: const []),
        ],
      );
      var llmCalled = 0;
      final detail = await wordRepo.lookupWord('homes', (_) async {
        llmCalled++;
        return null;
      });
      expect(llmCalled, 0);
      expect(detail, isNotNull);
      expect(detail!.spellingDisplay, 'home');
      expect(detail.inflection, isNotNull);
      expect(detail.inflection!.lemma, 'home');
      expect(detail.inflection!.type, InflectionType.sForm);
      expect(detail.inflection!.note, 'homes 是 home 的复数形式'); // 仅名词义项
    });

    test('plays 解析命中 play，义项含名词+动词时标注并列', () async {
      await wordRepo.saveLlmResult(
        'play', '/pleɪ/', const [
          WordSense(id: 0, orderIndex: 1, partOfSpeech: 'n.',
              chineseMeaning: '戏剧', englishDefinition: 'a stage performance',
              examples: const []),
          WordSense(id: 0, orderIndex: 2, partOfSpeech: 'v.',
              chineseMeaning: '玩耍', englishDefinition: 'to do an activity',
              examples: const []),
        ],
      );
      final detail = await wordRepo.lookupWord('plays', (_) async => null);
      expect(detail, isNotNull);
      expect(detail!.inflection!.note, 'plays 是 play 的复数形式 / 第三人称单数');
    });

    test('解析命中结果进 LRU 缓存（key=原词，第二次零查询）', () async {
      await wordRepo.saveLlmResult('box', null, const [
        WordSense(id: 0, orderIndex: 1, partOfSpeech: 'n.',
            chineseMeaning: '盒子', englishDefinition: 'a container',
            examples: const []),
      ]);
      final first = await wordRepo.lookupWord('boxes', (_) async => null);
      expect(first, isNotNull);
      expect(first!.inflection, isNotNull);
      // 第二次：LLM 不触发即可（缓存命中无法直接观测，间接验证）
      final second = await wordRepo.lookupWord('boxes', (_) async {
        fail('第二次查询不应走到 LLM');
      });
      expect(second!.wordId, first.wordId);
    });

    test('全部候选 miss → 正常走 LLM（含标注为 null）', () async {
      var llmCalled = 0;
      final detail = await wordRepo.lookupWord('xyzzy', (_) async {
        llmCalled++;
        return null;
      });
      expect(llmCalled, 1);
      expect(detail, isNull); // LLM 失败 → null（现有语义）
    });

    test('findLocal 同样解析（手动加词入口行为一致）', () async {
      await wordRepo.saveLlmResult('wife', null, const [
        WordSense(id: 0, orderIndex: 1, partOfSpeech: 'n.',
            chineseMeaning: '妻子', englishDefinition: 'a married woman',
            examples: const []),
      ]);
      final detail = await wordRepo.findLocal('wives');
      expect(detail, isNotNull);
      expect(detail!.spellingDisplay, 'wife');
      expect(detail.inflection, isNotNull);
    });
  });

  group('ArticleRepository', () {
    test('createBatch + createArticles + getArticles', () async {
      final batchId = await articleRepo.createBatch('LOW');
      expect(batchId, greaterThan(0));
      await articleRepo.createArticles(batchId, ['NEWS', 'SIMPLE_STORY']);

      final articles = await articleRepo.getArticles(batchId);
      expect(articles.length, 2);
      expect(articles[0].orderIndex, 1);
      expect(articles[0].contentCategory, 'NEWS');
      expect(articles[0].status, ArticleStatus.pending);
      expect(articles[0].batchId, batchId);
    });

    test('claimBatch / claimArticle CAS 语义', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);

      expect(await articleRepo.claimBatch(batchId), true);
      expect(await articleRepo.claimBatch(batchId), true); // GENERATING 可再认领
      await articleRepo.markBatchReady(batchId);
      expect(await articleRepo.claimBatch(batchId), false); // READY 拒绝

      final articleId = (await articleRepo.getArticles(batchId)).first.id;
      expect(await articleRepo.claimArticle(articleId), true);
      expect(await articleRepo.claimArticle(articleId), true);
      await articleRepo.failArticle(articleId, 'FAILED', errorCode: 'E1', errorMessage: '失败');
      expect(await articleRepo.claimArticle(articleId), true); // FAILED 可重试认领
    });

    test('completeArticle 写段落与成功状态', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      final articleId = (await articleRepo.getArticles(batchId)).first.id;

      await articleRepo.completeArticle(articleId, 'A title', [
        ArticleParagraph(orderIndex: -1, englishText: 'para 1', chineseTranslation: '段落一'),
        ArticleParagraph(orderIndex: 2, englishText: 'para 2', chineseTranslation: '段落二'),
      ], retryCount: 1);

      final article = await articleRepo.getArticle(articleId);
      expect(article!.status, ArticleStatus.success);
      expect(article.title, 'A title');
      expect(article.retryCount, 1);
      expect(article.paragraphs.length, 2);
      expect(article.paragraphs[0].orderIndex, 1); // <=0 用序号
      expect(article.paragraphs[1].orderIndex, 2);
    });

    test('isBatchComplete / hasFatalArticle', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS', 'SIMPLE_STORY']);
      expect(await articleRepo.isBatchComplete(batchId), false);

      final articles = await articleRepo.getArticles(batchId);
      await articleRepo.completeArticle(
          articles[0].id, 't1', const [], retryCount: 0);
      expect(await articleRepo.isBatchComplete(batchId), false);
      expect(await articleRepo.hasFatalArticle(batchId), false);

      await articleRepo.completeArticle(
          articles[1].id, 't2', const [], retryCount: 0);
      expect(await articleRepo.isBatchComplete(batchId), true);

      // 再建一个含 FATAL 的批次（不同日期，避免 (difficulty, generated_on) 唯一冲突）
      final batch2 = await articleRepo.createBatch('LOW', generatedOn: '2026-08-06');
      await articleRepo.createArticles(batch2, ['NEWS']);
      final a2 = (await articleRepo.getArticles(batch2)).first;
      await articleRepo.fatalArticle(a2.id, errorCode: 'F', errorMessage: 'fatal');
      expect(await articleRepo.hasFatalArticle(batch2), true);
    });

    test('markBatchBlocked：批次 BLOCKED + 错误流水账 + pipeline 开关', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);

      final logId = await articleRepo.markBatchBlocked(batchId, '结构性错误', 5);
      expect(logId, greaterThan(0));
      expect(await articleRepo.isPipelineBlocked(), true);

      final batch = await articleRepo.getBatchById(batchId);
      expect(batch!.status, BatchStatus.blocked);
      expect(batch.blockedReason, '结构性错误');

      final status = await db.select(db.generationPipelineStatuses).getSingleOrNull();
      expect(status!.isBlocked, true);
      expect(status.blockedAppVersionCode, 5);

      final errors = await db.select(db.generationErrorLogs).get();
      expect(errors.length, 1);
      expect(errors.first.entityType, 'BATCH');
      expect(errors.first.errorCode, 'STRUCTURAL_PIPELINE_BLOCKED');
    });

    test('recoverIfNewerVersion：新版本解锁并重置孤儿文章', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      final articleId = (await articleRepo.getArticles(batchId)).first.id;
      await articleRepo.claimArticle(articleId); // GENERATING
      await articleRepo.claimBatch(batchId);

      await articleRepo.markBatchBlocked(batchId, '原因', 5);
      expect(await articleRepo.recoverIfNewerVersion(5), false);
      expect(await articleRepo.recoverIfNewerVersion(6), true);
      expect(await articleRepo.isPipelineBlocked(), false);

      // 恢复只清 pipeline 开关与文章状态（Kotlin 语义：批次保持 BLOCKED，
      // 由 ActivateSeedBatch/生成编排在解锁后另行处理）
      final article = await articleRepo.getArticle(articleId);
      expect(article!.status, ArticleStatus.pending);
      final batch = await articleRepo.getBatchById(batchId);
      expect(batch!.status, BatchStatus.blocked);
    });

    test('failArticle / fatalArticle：状态 + 错误流水账同事务', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      final articleId = (await articleRepo.getArticles(batchId)).first.id;

      final logId = await articleRepo.failArticle(articleId, 'TIMEOUT',
          errorCode: 'TIMEOUT', errorMessage: '超时', errorHelp: '稍后重试', retryCount: 2);
      expect(logId, greaterThan(0));

      final article = await articleRepo.getArticle(articleId);
      expect(article!.status, ArticleStatus.timeout);
      // Kotlin 语义：updateStatusWithRetryTime 只写 status + last_retry_at，
      // retryCount 只进 error log，不进 article 行
      expect(article.retryCount, 0);
      expect(article.lastRetryAt, nowIso());

      final errors = await db.select(db.generationErrorLogs).get();
      expect(errors.length, 1);
      expect(errors.first.errorMessage, '超时');
      expect(errors.first.errorHelp, '稍后重试');
      expect(errors.first.retryCount, 2);

      // 无错误详情 → 返回 null，不写流水账
      final id2 = await articleRepo.failArticle(articleId, 'FAILED');
      expect(id2, isNull);
      expect((await db.select(db.generationErrorLogs).get()).length, 1);
    });

    test('错误流水账：markErrorNotified + getUnnotifiedErrors', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      final articleId = (await articleRepo.getArticles(batchId)).first.id;

      final logId = await articleRepo.failArticle(articleId, 'FAILED',
          errorCode: 'E', errorMessage: 'm');
      await articleRepo.markErrorNotified(logId!);

      final unnotified = await articleRepo.getUnnotifiedErrors('2000-01-01T00:00:00+08:00');
      expect(unnotified, isEmpty);
      final row = await db.select(db.generationErrorLogs).getSingle();
      expect(row.notifiedAt, isNotNull);
    });

    test('批次完成通知：markBatchReadyNotified + getReadyBatchesUnnotified', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      await articleRepo.markBatchReady(batchId);

      final unnotified = await articleRepo.getReadyBatchesUnnotified();
      expect(unnotified.map((b) => b.id), [batchId]);

      await articleRepo.markBatchReadyNotified(batchId);
      expect(await articleRepo.getReadyBatchesUnnotified(), isEmpty);
    });

    test('getBatchByDifficultyAndDate / findNextReadyBatch / 批次消费顺序', () async {
      // 批次 1、2 同难度；1 先 READY 并被消费
      final b1 = await articleRepo.createBatch('LOW', generatedOn: '2026-08-01');
      await articleRepo.createArticles(b1, ['NEWS']);
      await articleRepo.markBatchReady(b1);
      final b2 = await articleRepo.createBatch('LOW', generatedOn: '2026-08-02');
      await articleRepo.createArticles(b2, ['SIMPLE_STORY']);
      await articleRepo.markBatchReady(b2);

      expect((await articleRepo.getBatchByDifficultyAndDate('LOW', '2026-08-01'))!.id, b1);

      // 首次：最早的 READY
      final first = await articleRepo.findNextReadyBatch('LOW', null);
      expect(first!.id, b1);

      // 消费 b1
      expect(
          await articleRepo.assignBatchForToday(b1, '2026-08-01', 1),
          true);
      expect(
          await articleRepo.assignBatchForToday(b1, '2026-08-01', 1),
          false); // 今天已有记录

      expect(await articleRepo.getMaxRefBatchDate(), '2026-08-01');

      // afterDate 严格晚于已消费日期 → b2
      final next = await articleRepo.findNextReadyBatch('LOW', '2026-08-01');
      expect(next!.id, b2);
      // 已消费批次不再返回
      final afterB2 = await articleRepo.findNextReadyBatch('LOW', '2026-08-02');
      expect(afterB2, isNull);
    });

    test('getAssignedBatchForDate / getAllDailyLearningInfos', () async {
      final b1 = await articleRepo.createBatch('LOW', generatedOn: '2026-08-01');
      await articleRepo.createArticles(b1, ['NEWS']);
      await articleRepo.markBatchReady(b1);
      await articleRepo.assignBatchForToday(b1, '2026-08-01', 1);

      final today = nowDate();
      final assigned = await articleRepo.getAssignedBatchForDate(today);
      expect(assigned!.id, b1);

      final infos = await articleRepo.getAllDailyLearningInfos();
      expect(infos.length, 1);
      expect(infos.first.learningDate, today);
      expect(infos.first.dailyCountSnapshot, 1);
      expect(infos.first.batch.id, b1);
    });

    test('getUnassignedReadyBatches：默认 minGeneratedOn 为今天', () async {
      // 默认 minGeneratedOn = 今天 → 生成于过去（8-01）的批次被排除（忽略旧 seed 数据）
      final b1 = await articleRepo.createBatch('LOW', generatedOn: '2026-08-01');
      await articleRepo.createArticles(b1, ['NEWS']);
      await articleRepo.markBatchReady(b1);
      // 今天生成的批次同样被排除（generated_on 严格大于 minGeneratedOn）
      final b2 = await articleRepo.createBatch('LOW', generatedOn: '2026-08-07');
      await articleRepo.createArticles(b2, ['NEWS']);
      await articleRepo.markBatchReady(b2);

      expect(await articleRepo.getUnassignedReadyBatches('LOW', null), isEmpty);

      // 显式传更早日期 → 两批都返回
      final all = await articleRepo.getUnassignedReadyBatches('LOW', '2026-07-01');
      expect(all.map((b) => b.id), [b1, b2]);
    });

    test('阅读计时：addReadSeconds + tryMarkReadCompleted + force', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      final articleId = (await articleRepo.getArticles(batchId)).first.id;

      await articleRepo.addReadSeconds(articleId, 50);
      await articleRepo.addReadSeconds(articleId, 50);
      await articleRepo.tryMarkReadCompleted(articleId);
      var article = await articleRepo.getArticle(articleId);
      expect(article!.accumulatedReadSeconds, 100);
      expect(article.readCompletedAt, isNull); // 未到 120s

      await articleRepo.addReadSeconds(articleId, 20);
      await articleRepo.tryMarkReadCompleted(articleId);
      article = await articleRepo.getArticle(articleId);
      expect(article!.accumulatedReadSeconds, 120);
      expect(article.readCompletedAt, nowIso());

      // 幂等：不再回写
      await articleRepo.tryMarkReadCompleted(articleId);
      article = await articleRepo.getArticle(articleId);
      expect(article!.readCompletedAt, nowIso());
    });

    test('forceMarkReadCompleted：无视累计秒数', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      final articleId = (await articleRepo.getArticles(batchId)).first.id;
      await articleRepo.forceMarkReadCompleted(articleId);
      expect((await articleRepo.getArticle(articleId))!.readCompletedAt, nowIso());
    });

    test('reconcileOrphanArticles：重置 GENERATING/TIMEOUT/FAILED 文章与批次', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      final articleId = (await articleRepo.getArticles(batchId)).first.id;
      await articleRepo.claimArticle(articleId); // GENERATING
      await articleRepo.claimBatch(batchId); // GENERATING

      await articleRepo.reconcileOrphanArticles();
      final article = await articleRepo.getArticle(articleId);
      expect(article!.status, ArticleStatus.pending);
      final batch = await articleRepo.getBatchById(batchId);
      expect(batch!.status, BatchStatus.pending);
    });

    test('getGeneratingBatches', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      expect(await articleRepo.getGeneratingBatches(), isEmpty);
      await articleRepo.claimBatch(batchId);
      expect((await articleRepo.getGeneratingBatches()).map((b) => b.id), [batchId]);
    });

    test('observeArticles 流：插入触发更新', () async {
      final batchId = await articleRepo.createBatch('LOW');
      // drift watch 订阅即发首帧（空列表），跳过首帧取插入后的第二帧
      final emission = articleRepo.observeArticles(batchId).skip(1).first;
      await articleRepo.createArticles(batchId, ['NEWS', 'SIMPLE_STORY']);
      final articles = await emission;
      expect(articles.length, 2);
      expect(articles[0].contentCategory, 'NEWS');
    });

    test('observeGenerationErrors 流：每篇文章只取最新错误', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      final articleId = (await articleRepo.getArticles(batchId)).first.id;

      await articleRepo.failArticle(articleId, 'TIMEOUT',
          errorCode: 'T1', errorMessage: '第一次');
      await articleRepo.failArticle(articleId, 'FAILED',
          errorCode: 'F2', errorMessage: '第二次');
      // 订阅后首帧即当前状态（drift watch 语义）：只含最新错误
      final errors = await articleRepo.observeGenerationErrors().first;
      expect(errors.length, 1);
      expect(errors.first.errorMessage, '第二次');
      expect(errors.first.status, 'FAILED');
    });

    test('resetArticleForRetry', () async {
      final batchId = await articleRepo.createBatch('LOW');
      await articleRepo.createArticles(batchId, ['NEWS']);
      final articleId = (await articleRepo.getArticles(batchId)).first.id;
      await articleRepo.failArticle(articleId, 'FAILED', errorCode: 'E', errorMessage: 'm');
      await articleRepo.resetArticleForRetry(articleId);
      final article = await articleRepo.getArticle(articleId);
      expect(article!.status, ArticleStatus.pending);
      expect(article.retryCount, 0);
    });
  });

  group('VocabularyRepository', () {
    test('addWord：新词创建条目，已 active 返回 null', () async {
      final saved = await wordRepo.saveLlmResult(
          'apple', '/ˈæpəl/', [sense(0)], normalized: 'apple');
      final entryId = await vocabRepo.addWord(saved.wordId);
      expect(entryId, greaterThan(0));

      // 已 active → null
      expect(await vocabRepo.addWord(saved.wordId), isNull);
      expect(await vocabRepo.getActiveCount(), 1);
    });

    test('markCorrect：阈值 1 直接 MASTERED；阈值 >1 达阈值才 MASTERED', () async {
      final saved = await wordRepo.saveLlmResult(
          'apple', null, [sense(0)], normalized: 'apple');
      final id = (await vocabRepo.addWord(saved.wordId))!;

      // 阈值 1 → 立即 MASTERED
      await vocabRepo.markCorrect(id, masteryThreshold: 1);
      var entry = await db.select(db.vocabularyEntries).getSingle();
      expect(entry.status, 'MASTERED');
      expect(entry.correctReviewStreak, 1);
      expect(await vocabRepo.getActiveCount(), 0);
    });

    test('markCorrect：阈值 3 两次不达，三次达成', () async {
      final saved = await wordRepo.saveLlmResult(
          'banana', null, [sense(0)], normalized: 'banana');
      final id = (await vocabRepo.addWord(saved.wordId))!;

      await vocabRepo.markCorrect(id, masteryThreshold: 3);
      await vocabRepo.markCorrect(id, masteryThreshold: 3);
      var entry = await db.select(db.vocabularyEntries).getSingle();
      expect(entry.status, 'LEARNING');
      expect(entry.correctReviewStreak, 2);

      await vocabRepo.markCorrect(id, masteryThreshold: 3);
      entry = await db.select(db.vocabularyEntries).getSingle();
      expect(entry.status, 'MASTERED');
      // markMastered 的 SQL 也是 +1（Kotlin 一致）：MASTERED 时 streak 为 4
      expect(entry.correctReviewStreak, 4);
    });

    test('markIncorrect：重置 streak', () async {
      final saved = await wordRepo.saveLlmResult(
          'cherry', null, [sense(0)], normalized: 'cherry');
      final id = (await vocabRepo.addWord(saved.wordId))!;
      await vocabRepo.markCorrect(id, masteryThreshold: 3);
      await vocabRepo.markCorrect(id, masteryThreshold: 3);
      await vocabRepo.markIncorrect(id);
      final entry = await db.select(db.vocabularyEntries).getSingle();
      expect(entry.correctReviewStreak, 0);
      expect(entry.status, 'LEARNING');
    });

    test('removeWord：软删除并记录原因', () async {
      final saved = await wordRepo.saveLlmResult(
          'dog', null, [sense(0)], normalized: 'dog');
      final id = (await vocabRepo.addWord(saved.wordId))!;
      await vocabRepo.removeWord(id, reason: 'MANUAL_REMOVAL');
      expect(await vocabRepo.getActiveCount(), 0);
      expect(await vocabRepo.countDistinctWords(), 0);
      final row = await db.select(db.vocabularyEntries).getSingle();
      expect(row.deletedReason, 'MANUAL_REMOVAL');
      expect(row.deletedAt, nowIso());
    });

    test('getActiveWords / observeActive：拼装 VocabWord（含释义）', () async {
      final saved = await wordRepo.saveLlmResult(
          'apple',
          '/ˈæpəl/',
          [
            WordSense(
              id: -1,
              orderIndex: 0,
              partOfSpeech: 'n.',
              chineseMeaning: '苹果',
              englishDefinition: 'a fruit',
              examples: const [],
            ),
          ],
          normalized: 'apple');
      await vocabRepo.addWord(saved.wordId);

      final emission = vocabRepo.observeActive().first;
      final active = await emission;
      expect(active.length, 1);
      expect(active.first.spellingDisplay, 'apple');
      expect(active.first.phoneticIpa, '/ˈæpəl/');
      expect(active.first.status, VocabStatus.new_);
      expect(active.first.allSenses.first.chineseMeaning, '苹果');
      expect(active.first.entryId, greaterThan(0));

      // 单次查询一致
      final oneShot = await vocabRepo.getActiveWords();
      expect(oneShot.length, 1);
      expect(oneShot.first.wordId, saved.wordId);
    });

    test('countDistinctWords', () async {
      final a = await wordRepo.saveLlmResult(
          'a', null, [sense(0)], normalized: 'a');
      final b = await wordRepo.saveLlmResult(
          'b', null, [sense(0)], normalized: 'b');
      await vocabRepo.addWord(a.wordId);
      await vocabRepo.addWord(b.wordId);
      expect(await vocabRepo.countDistinctWords(), 2);
    });
  });

  group('SettingsRepository', () {
    test('默认无设置；completeOnboarding 后可读', () async {
      expect(await settingsRepo.getSettings(), isNull);
      expect(await settingsRepo.isOnboarded(), false);

      await settingsRepo.completeOnboarding('HIGH', 5);
      final s = await settingsRepo.getSettings();
      expect(s!.isOnboarded, true);
      expect(s.difficultyLevel, 'HIGH');
      expect(s.dailyArticleCount, 5);
      expect(await settingsRepo.isOnboarded(), true);
    });

    test('observeSettings 流：upsert 触发更新', () async {
      // 首帧为 null（无行），跳过首帧取 upsert 后的第二帧
      final emission = settingsRepo.observeSettings().skip(1).first;
      await settingsRepo.completeOnboarding('LOW', 2);
      final s = await emission;
      expect(s!.difficultyLevel, 'LOW');
    });

    test('updateLevel / updateTranslationMode / updateAutoPlayAudio', () async {
      await settingsRepo.completeOnboarding('LOW', 2);
      await settingsRepo.updateLevel('MEDIUM');
      await settingsRepo.updateTranslationMode('HIDDEN');
      await settingsRepo.updateAutoPlayAudio(true);
      final s = await settingsRepo.getSettings();
      expect(s!.difficultyLevel, 'MEDIUM');
      expect(s.translationDisplayMode, 'HIDDEN');
      expect(s.autoPlayAudio, true);
    });

    test('updateDailyArticleCount：校验 1..5，同值返回 false', () async {
      await settingsRepo.completeOnboarding('LOW', 3);
      expect(await settingsRepo.updateDailyArticleCount(3), false);
      expect(await settingsRepo.updateDailyArticleCount(5), true);
      expect(await settingsRepo.updateDailyArticleCount(6), false);
      expect(await settingsRepo.updateDailyArticleCount(0), false);
      expect((await settingsRepo.getSettings())!.dailyArticleCount, 5);
    });

    test('updateMasteryThreshold：夹取 1..5', () async {
      await settingsRepo.completeOnboarding('LOW', 2);
      await settingsRepo.updateMasteryThreshold(9);
      expect((await settingsRepo.getSettings())!.masteryThresholdN, 5);
      await settingsRepo.updateMasteryThreshold(0);
      expect((await settingsRepo.getSettings())!.masteryThresholdN, 1);
    });

    test('无设置时更新操作不崩溃', () async {
      await settingsRepo.updateLevel('HIGH');
      await settingsRepo.updateDailyArticleCount(3);
      await settingsRepo.updateTranslationMode('BLURRED');
      await settingsRepo.updateMasteryThreshold(2);
      await settingsRepo.updateAutoPlayAudio(true);
      expect(await settingsRepo.getSettings(), isNull);
    });
  });

  group('StatsRepository', () {
    test('recordReadingActivity：新日期建行，同日累加', () async {
      await statsRepo.recordReadingActivity(secondsSpent: 60);
      var stats = await statsRepo.getStats();
      expect(stats!.totalArticlesRead, 1);
      expect(stats.currentStreak, 1);
      expect(stats.totalLearningDays, 1);
      expect(stats.lastActiveDate, nowDate());

      await statsRepo.recordReadingActivity(secondsSpent: 30);
      stats = await statsRepo.getStats();
      expect(stats!.totalArticlesRead, 2);

      final log = await db.select(db.dailyLearningLogs).getSingle();
      expect(log.articlesRead, 2);
      expect(log.secondsSpent, 90);
    });

    test('recordWordAdded：记录词数并重算', () async {
      final a = await wordRepo.saveLlmResult(
          'a', null, [sense(0)], normalized: 'a');
      await vocabRepo.addWord(a.wordId);
      await statsRepo.recordWordAdded();

      final stats = await statsRepo.getStats();
      expect(stats!.totalWordsAdded, 1);
      expect(stats.totalArticlesRead, 0);
      expect(stats.currentStreak, 1);
    });

    test('连续活跃日期计算 streak', () async {
      final logDao = DailyLearningLogDao(db);
      await logDao.upsert(DailyLearningLogsCompanion(
        logDate: const Value('2026-08-05'),
        articlesRead: const Value(1),
        wordsAdded: const Value(0),
        secondsSpent: const Value(0),
      ));
      await logDao.upsert(DailyLearningLogsCompanion(
        logDate: const Value('2026-08-06'),
        articlesRead: const Value(1),
        wordsAdded: const Value(0),
        secondsSpent: const Value(0),
      ));
      // 今天（2026-08-07）由 recordReadingActivity 写入
      await statsRepo.recordReadingActivity(secondsSpent: 10);
      final stats = await statsRepo.getStats();
      expect(stats!.currentStreak, 3);
      expect(stats.longestStreak, 3);
      expect(stats.totalLearningDays, 3);
      expect(stats.totalArticlesRead, 3);
    });

    test('中断后 streak 归零但 longestStreak 保留', () async {
      final logDao = DailyLearningLogDao(db);
      await logDao.upsert(DailyLearningLogsCompanion(
        logDate: const Value('2026-08-05'),
        articlesRead: const Value(1),
        wordsAdded: const Value(0),
        secondsSpent: const Value(0),
      ));
      // 今天活跃 → 昨天(8/6)缺失 → 中断
      await statsRepo.recordReadingActivity(secondsSpent: 10);
      var stats = await statsRepo.getStats();
      expect(stats!.currentStreak, 1);
      expect(stats.longestStreak, 1);

      // 明天活跃：8/8 与 8/7 连续 → streak 2（8/6 缺失中断）
      now = DateTime(2026, 8, 8, 10, 30, 0);
      await statsRepo.recordReadingActivity(secondsSpent: 10);
      stats = await statsRepo.getStats();
      expect(stats!.currentStreak, 2);
      expect(stats.longestStreak, 2);
    });

    test('观察流 observeStats', () async {
      final emission = statsRepo.observeStats().skip(1).first;
      await statsRepo.recordReadingActivity(secondsSpent: 10);
      final stats = await emission;
      expect(stats!.totalArticlesRead, 1);
    });
  });
}
