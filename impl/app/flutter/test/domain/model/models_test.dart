import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/domain/inflection/inflection_resolver.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/model/generation_error.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/model/word_detail.dart';

void main() {
  group('ArticleStatus', () {
    test('fromDbValue 解析枚举名', () {
      expect(ArticleStatus.fromDbValue('PENDING'), ArticleStatus.pending);
      expect(ArticleStatus.fromDbValue('GENERATING'), ArticleStatus.generating);
      expect(ArticleStatus.fromDbValue('SUCCESS'), ArticleStatus.success);
      expect(ArticleStatus.fromDbValue('TIMEOUT'), ArticleStatus.timeout);
      expect(ArticleStatus.fromDbValue('FAILED'), ArticleStatus.failed);
      expect(ArticleStatus.fromDbValue('FATAL'), ArticleStatus.fatal);
    });
    test('未知枚举值抛 ArgumentError', () {
      expect(() => ArticleStatus.fromDbValue('XXX'), throwsArgumentError);
    });
    test('toDbValue 返回大写枚举名', () {
      expect(ArticleStatus.success.toDbValue(), 'SUCCESS');
      expect(ArticleStatus.timeout.toDbValue(), 'TIMEOUT');
    });
    test('toString 与 Kotlin 一致（输出大写枚举名）', () {
      expect(ArticleStatus.timeout.toString(), 'TIMEOUT');
    });
  });

  group('BatchStatus', () {
    test('fromDbValue 解析枚举名', () {
      expect(BatchStatus.fromDbValue('PENDING'), BatchStatus.pending);
      expect(BatchStatus.fromDbValue('GENERATING'), BatchStatus.generating);
      expect(BatchStatus.fromDbValue('READY'), BatchStatus.ready);
      expect(BatchStatus.fromDbValue('CURRENT'), BatchStatus.current);
      expect(BatchStatus.fromDbValue('BLOCKED'), BatchStatus.blocked);
    });
    test('未知枚举值抛 ArgumentError', () {
      expect(() => BatchStatus.fromDbValue('XXX'), throwsArgumentError);
    });
    test('toDbValue / toString', () {
      expect(BatchStatus.ready.toDbValue(), 'READY');
      expect(BatchStatus.generating.toString(), 'GENERATING');
    });
  });

  group('VocabStatus', () {
    test('fromDbValue 解析枚举名', () {
      expect(VocabStatus.fromDbValue('NEW'), VocabStatus.new_);
      expect(VocabStatus.fromDbValue('LEARNING'), VocabStatus.learning);
      expect(VocabStatus.fromDbValue('MASTERED'), VocabStatus.mastered);
    });
    test('未知枚举值抛 ArgumentError', () {
      expect(() => VocabStatus.fromDbValue('XXX'), throwsArgumentError);
    });
    test('toDbValue / toString', () {
      expect(VocabStatus.mastered.toDbValue(), 'MASTERED');
      expect(VocabStatus.new_.toString(), 'NEW');
    });
  });

  group('DifficultyLevel', () {
    test('fromDbValue 解析枚举名', () {
      expect(DifficultyLevel.fromDbValue('LOW'), DifficultyLevel.low);
      expect(DifficultyLevel.fromDbValue('MEDIUM'), DifficultyLevel.medium);
      expect(DifficultyLevel.fromDbValue('HIGH'), DifficultyLevel.high);
    });
    test('未知枚举值抛 ArgumentError', () {
      expect(() => DifficultyLevel.fromDbValue('XXX'), throwsArgumentError);
    });
    test('toDbValue / toString', () {
      expect(DifficultyLevel.medium.toDbValue(), 'MEDIUM');
      expect(DifficultyLevel.high.toString(), 'HIGH');
    });
  });

  group('TranslationDisplayMode', () {
    test('fromDbValue 只映射 FULL/BLURRED/HIDDEN', () {
      expect(TranslationDisplayMode.fromDbValue('FULL'), TranslationDisplayMode.full);
      expect(
        TranslationDisplayMode.fromDbValue('BLURRED'),
        TranslationDisplayMode.blurred,
      );
      expect(TranslationDisplayMode.fromDbValue('HIDDEN'), TranslationDisplayMode.hidden);
    });
    test('DIM 不映射（仅 UI 显示用），未知值抛 ArgumentError', () {
      expect(() => TranslationDisplayMode.fromDbValue('DIM'), throwsArgumentError);
      expect(() => TranslationDisplayMode.fromDbValue('XXX'), throwsArgumentError);
    });
    test('DIM 禁止持久化（toDbValue 抛 StateError）', () {
      expect(() => TranslationDisplayMode.dim.toDbValue(), throwsStateError);
    });
    test('toDbValue / toString', () {
      expect(TranslationDisplayMode.blurred.toDbValue(), 'BLURRED');
      expect(TranslationDisplayMode.dim.toString(), 'DIM');
    });
  });

  group('ContentCategory', () {
    test('全集 12 个值', () {
      expect(ContentCategory.values.length, 12);
    });
    test('fromDbValue 解析枚举名', () {
      expect(ContentCategory.fromDbValue('DAILY_CONVERSATION'), ContentCategory.dailyConversation);
      expect(ContentCategory.fromDbValue('NEWS'), ContentCategory.news);
      expect(
        ContentCategory.fromDbValue('CLASSIC_NOVEL_EXCERPT'),
        ContentCategory.classicNovelExcerpt,
      );
      expect(ContentCategory.fromDbValue('ACADEMIC_EXCERPT'), ContentCategory.academicExcerpt);
      expect(ContentCategory.fromDbValue('DEBATE_SPEECH'), ContentCategory.debateSpeech);
      expect(ContentCategory.fromDbValue('LEGAL_DOCUMENT'), ContentCategory.legalDocument);
    });
    test('未知枚举值抛 ArgumentError', () {
      expect(() => ContentCategory.fromDbValue('XXX'), throwsArgumentError);
    });
    test('toDbValue / toString', () {
      expect(ContentCategory.dailyConversation.toDbValue(), 'DAILY_CONVERSATION');
      expect(ContentCategory.news.toString(), 'NEWS');
    });
  });

  group('模型默认值', () {
    test('Article：maxRetries=3、nextRetryAt=null、paragraphs=[]', () {
      final a = Article(
        id: 1,
        batchId: 2,
        orderIndex: 3,
        contentCategory: 'NEWS',
        title: null,
        status: ArticleStatus.success,
        generationStartedAt: null,
        generationCompletedAt: null,
        retryCount: 0,
        accumulatedReadSeconds: 0,
        readCompletedAt: null,
        lastRetryAt: null,
      );
      expect(a.maxRetries, 3);
      expect(a.nextRetryAt, isNull);
      expect(a.paragraphs, isEmpty);
    });

    test('ArticleBatch：blockedReason=null、blockedAt=null、articles=[]', () {
      final b = ArticleBatch(
        id: 1,
        status: BatchStatus.generating,
        difficultyLevelSnapshot: 'LOW',
        generatedOn: null,
        lastUpdatedAt: '2026-08-07T10:00:00+08:00',
      );
      expect(b.blockedReason, isNull);
      expect(b.blockedAt, isNull);
      expect(b.articles, isEmpty);
    });

    test('WordDetail：isInVocabulary=false、vocabularyEntryId=null', () {
      final w = WordDetail(
        wordId: 1,
        spellingDisplay: 'apple',
        phoneticIpa: null,
        primarySense: null,
        allSenses: [],
      );
      expect(w.isInVocabulary, isFalse);
      expect(w.vocabularyEntryId, isNull);
    });

    test('UserSettings：全部默认值', () {
      final s = UserSettings();
      expect(s.id, 1);
      expect(s.isOnboarded, isFalse);
      expect(s.difficultyLevel, 'MEDIUM');
      expect(s.dailyArticleCount, 3);
      expect(s.translationDisplayMode, 'FULL');
      expect(s.masteryThresholdN, 1);
      expect(s.autoPlayAudio, isFalse);
    });

    test('GenerationError：entityType=ARTICLE、status=null', () {
      final e = GenerationError(
        id: 1,
        entityId: 1,
        errorCode: 'E1',
        errorMessage: 'm',
        errorHelp: null,
        retryCount: 0,
        createdAt: '2026-08-07T10:00:00+08:00',
      );
      expect(e.entityType, 'ARTICLE');
      expect(e.status, isNull);
    });
  });

  group('toString 语义（对齐 Kotlin data class）', () {
    test('UserSettings 默认值 toString 与 Kotlin 完全一致', () {
      expect(
        UserSettings().toString(),
        'UserSettings(id=1, isOnboarded=false, difficultyLevel=MEDIUM, '
        'dailyArticleCount=3, translationDisplayMode=FULL, '
        'ttsSpeed=1.0, ttsVoice=TtsVoice.bella, '
        'masteryThresholdN=1, autoPlayAudio=false)',
      );
    });

    test('Article toString 中枚举输出大写名', () {
      final a = Article(
        id: 1,
        batchId: 2,
        orderIndex: 3,
        contentCategory: 'NEWS',
        title: 'T',
        status: ArticleStatus.success,
        generationStartedAt: null,
        generationCompletedAt: null,
        retryCount: 0,
        accumulatedReadSeconds: 0,
        readCompletedAt: null,
        lastRetryAt: null,
      );
      expect(a.toString(), 'Article(id=1, batchId=2, orderIndex=3, '
          'contentCategory=NEWS, title=T, status=SUCCESS, '
          'generationStartedAt=null, generationCompletedAt=null, retryCount=0, '
          'accumulatedReadSeconds=0, readCompletedAt=null, lastRetryAt=null, '
          'maxRetries=3, nextRetryAt=null, paragraphs=[])');
    });
  });

  group('WordDetail.inflection（词形解析标注）', () {
    test('默认 null', () {
      final w = WordDetail(
        wordId: 1,
        spellingDisplay: 'home',
        phoneticIpa: null,
        primarySense: null,
        allSenses: const [],
      );
      expect(w.inflection, isNull);
    });

    test('copyWith 设置与保留', () {
      final w = WordDetail(
        wordId: 1,
        spellingDisplay: 'home',
        phoneticIpa: null,
        primarySense: null,
        allSenses: const [],
      );
      final result = const InflectionResult(
        lemma: 'home',
        type: InflectionType.sForm,
        note: 'homes 是 home 的复数形式',
      );
      final withInflection = w.copyWith(inflection: result);
      expect(withInflection.inflection, same(result));
      expect(withInflection.copyWith().inflection, same(result)); // 保留
    });
  });
}
