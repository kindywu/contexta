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
      ArticleBatchDao(db),
      ArticleDao(db),
      ArticleParagraphDao(db),
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
      // 缓存命中返回同一实例（M-2）：与"重新解析出的新实例"可区分
      expect(identical(second, first), isTrue);
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

    test('sForm 仅动词义项：cries → 第三人称单数标注（hasVerb 分支）', () async {
      await wordRepo.saveLlmResult('cry', null, const [
        WordSense(id: 0, orderIndex: 1, partOfSpeech: 'v.',
            chineseMeaning: '哭', englishDefinition: 'to shed tears',
            examples: const []),
      ]);
      final detail = await wordRepo.lookupWord('cries', (_) async => null);
      expect(detail, isNotNull);
      expect(detail!.inflection!.lemma, 'cry');
      expect(detail.inflection!.type, InflectionType.sForm);
      expect(detail.inflection!.note, 'cries 是 cry 的第三人称单数形式');
    });

    test('pastTense：played → 过去式/过去分词标注', () async {
      await wordRepo.saveLlmResult('play', '/pleɪ/', const [
        WordSense(id: 0, orderIndex: 1, partOfSpeech: 'v.',
            chineseMeaning: '玩', englishDefinition: 'to do an activity',
            examples: const []),
      ]);
      final detail = await wordRepo.lookupWord('played', (_) async => null);
      expect(detail, isNotNull);
      expect(detail!.inflection!.type, InflectionType.pastTense);
      expect(detail.inflection!.note, 'played 是 play 的过去式/过去分词');
    });

    test('词元本体（DB 精确命中）不带 inflection 标注（M-4）', () async {
      await wordRepo.saveLlmResult('home', null, const [
        WordSense(id: 0, orderIndex: 1, partOfSpeech: 'n.',
            chineseMeaning: '家', englishDefinition: 'a place where you live',
            examples: const []),
      ]);
      final detail = await wordRepo.lookupWord('home', (_) async => null);
      expect(detail, isNotNull);
      expect(detail!.inflection, isNull);
    });

    test('adv./pron. 等词性不误判为名/动词（I-1 回归）', () async {
      await wordRepo.saveLlmResult('fast', '/fæst/', const [
        WordSense(id: 0, orderIndex: 1, partOfSpeech: 'adv.',
            chineseMeaning: '快速地', englishDefinition: 'quickly',
            examples: const []),
        WordSense(id: 0, orderIndex: 2, partOfSpeech: 'pron.',
            chineseMeaning: '某物', englishDefinition: 'somebody',
            examples: const []),
      ]);
      final detail = await wordRepo.lookupWord('fasts', (_) async => null);
      expect(detail, isNotNull);
      expect(detail!.inflection!.note, 'fasts 是 fast 的复数形式');
    });
  });

  group('ArticleRepository', () {
    /// 直连 DAO 插入 READY 批次 + SUCCESS 文章（T6 后仓储不再提供
    /// createArticles/markBatchReady，测试用 DAO 构造等价数据）。
    Future<int> insertReadyBatchWithArticles(String difficulty,
        {required String generatedOn, List<String> categories = const ['NEWS']}) async {
      final batchId = await db.into(db.articleBatches).insert(
          ArticleBatchesCompanion.insert(
            status: 'READY',
            difficultyLevelSnapshot: difficulty,
            generatedOn: generatedOn,
            lastUpdatedAt: nowIso(),
          ));
      for (var i = 0; i < categories.length; i++) {
        await db.into(db.articles).insert(ArticlesCompanion.insert(
              batchId: batchId,
              orderIndex: i + 1,
              contentCategory: categories[i],
              title: Value('T$i'),
              status: 'SUCCESS',
              accumulatedReadSeconds: 0,
            ));
      }
      return batchId;
    }

    test('getBatchByDifficultyAndDate / findNextReadyBatch / 批次消费顺序', () async {
      // 批次 1、2 同难度；1 先 READY 并被消费
      final b1 = await insertReadyBatchWithArticles('LOW', generatedOn: '2026-08-01');
      final b2 = await insertReadyBatchWithArticles('LOW', generatedOn: '2026-08-02');

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

      // afterDate 不早于已消费日期（>=，2026-08-12 修复）→ b2
      final next = await articleRepo.findNextReadyBatch('LOW', '2026-08-01');
      expect(next!.id, b2);
      // == afterDate 的未消费批次也可选（批次等得起，断签可自愈）
      final afterB2 = await articleRepo.findNextReadyBatch('LOW', '2026-08-02');
      expect(afterB2!.id, b2);
    });

    test('getAssignedBatchForDate / getAllDailyLearningInfos', () async {
      final b1 = await insertReadyBatchWithArticles('LOW', generatedOn: '2026-08-01');
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

    test('阅读计时：addReadSeconds + tryMarkReadCompleted + force', () async {
      final batchId = await insertReadyBatchWithArticles('LOW', generatedOn: '2026-08-01');
      final articleQuery = db.select(db.articles)
        ..where((t) => t.batchId.equals(batchId));
      final articleId = (await articleQuery.getSingle()).id;

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
      final batchId = await insertReadyBatchWithArticles('LOW', generatedOn: '2026-08-01');
      final articleQuery = db.select(db.articles)
        ..where((t) => t.batchId.equals(batchId));
      final articleId = (await articleQuery.getSingle()).id;
      await articleRepo.forceMarkReadCompleted(articleId);
      expect((await articleRepo.getArticle(articleId))!.readCompletedAt, nowIso());
    });

    test('observeArticles 流：插入触发更新', () async {
      final batchId = await db.into(db.articleBatches).insert(
          ArticleBatchesCompanion.insert(
            status: 'CURRENT',
            difficultyLevelSnapshot: 'LOW',
            generatedOn: '2026-08-01',
            lastUpdatedAt: nowIso(),
          ));
      // drift watch 订阅即发首帧（空列表），跳过首帧取插入后的第二帧
      final emission = articleRepo.observeArticles(batchId).skip(1).first;
      await db.batch((b) => b.insertAll(db.articles, [
            for (var i = 0; i < 2; i++)
              ArticlesCompanion.insert(
                batchId: batchId,
                orderIndex: i + 1,
                contentCategory: ['NEWS', 'SIMPLE_STORY'][i],
                title: Value('T$i'),
                status: 'SUCCESS',
                accumulatedReadSeconds: 0,
              ),
          ]));
      final articles = await emission;
      expect(articles.length, 2);
      expect(articles[0].contentCategory, 'NEWS');
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
