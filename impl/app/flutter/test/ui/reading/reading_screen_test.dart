import 'dart:async';

import 'package:contexta/core/components/app_modal.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/llm_client.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/model/word_detail.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/repository/word_repository.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/reading/reading_controller.dart';
import 'package:contexta/ui/reading/reading_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading 页 widget 测试（Task 24：播放条 + 查词弹窗 + TTS 不可用 toast）。
/// 状态机/查词逻辑已由 reading_controller_test 覆盖，此处验证 UI 接线。
///
/// 数据流（对照 Kotlin）：点击正文单词 → showWordSheet → 弹窗先显示
/// loading 再回填义项；加入生词表即时更新弹窗按钮与正文高亮；TTS 不可用
/// 时顶部 toast 显示 4s 后自动消失。

/// 组合桩：实现 Reading 页依赖的全部仓储/客户端接口，测试可控配置。
class _Stub implements ArticleRepository, SettingsRepository,
    VocabularyRepository, StatsRepository, WordRepository, LlmClient {
  Article? article;
  UserSettings settings = const UserSettings(isOnboarded: true);
  WordDetail? lookupResult;

  /// 非 null 时 lookupWord 挂起，由测试手动 complete（loading 态断言用）。
  Completer<WordDetail?>? lookupCompleter;
  int? addWordEntryId;
  int readingCount = 0;

  @override
  Future<Article?> getArticle(int articleId) async => article;

  @override
  Future<UserSettings?> getSettings() async => settings;

  @override
  Future<List<VocabWord>> getActiveWords() async => const [];

  @override
  Future<void> recordReadingActivity({int secondsSpent = 0}) async {
    readingCount++;
  }

  @override
  Future<WordDetail?> lookupWord(
      String spelling, Future<WordDetail?> Function(String) llmFallback) {
    final completer = lookupCompleter;
    if (completer != null) return completer.future;
    return Future.value(lookupResult);
  }

  @override
  Future<int?> addWord(int wordId) async => addWordEntryId;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// TTS 桩：unavailable 时可配（toast 测试用）。
class _TtsStub implements TtsEngine {
  bool available = true;
  int stopCount = 0;
  final List<String> spoken = [];

  @override
  bool isAvailable() => available;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0}) {
    if (!available) return null;
    spoken.add(text);
    return 'ctx-1';
  }

  @override
  void stop() {
    stopCount++;
  }

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {}
}

Article makeArticle() => const Article(
      id: 1,
      batchId: 1,
      orderIndex: 0,
      contentCategory: 'NEWS',
      title: 'A Day',
      status: ArticleStatus.success,
      generationStartedAt: null,
      generationCompletedAt: '2026-08-07T12:00:00+08:00',
      retryCount: 0,
      accumulatedReadSeconds: 0,
      readCompletedAt: null,
      lastRetryAt: null,
      paragraphs: [
        ArticleParagraph(
          orderIndex: 0,
          englishText: 'Hello',
          chineseTranslation: '你好世界。',
        ),
      ],
    );

void main() {
  late _Stub stub;
  late _TtsStub tts;

  setUp(() {
    stub = _Stub()..article = makeArticle();
    tts = _TtsStub();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        articleRepositoryProvider.overrideWithValue(stub),
        settingsRepositoryProvider.overrideWithValue(stub),
        vocabularyRepositoryProvider.overrideWithValue(stub),
        statsRepositoryProvider.overrideWithValue(stub),
        wordRepositoryProvider.overrideWithValue(stub),
        llmClientProvider.overrideWithValue(stub),
        ttsEngineProvider.overrideWith((ref) async => tts),
      ],
      child: MaterialApp(
        home: ReadingScreen(articleId: 1, onBack: () {}),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('播放条', () {
    testWidgets('常驻底部：播放按钮 + 朗读全文 + 1x 语速胶囊', (tester) async {
      await pumpScreen(tester);

      expect(find.text('朗读全文'), findsOneWidget);
      expect(find.text('1x'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('点击语速胶囊切换 0.75x → 再点回 1x', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('1x'));
      await tester.pump();
      expect(find.text('0.75x'), findsOneWidget);

      await tester.tap(find.text('0.75x'));
      await tester.pump();
      expect(find.text('1x'), findsOneWidget);
    });
  });

  group('TTS 不可用', () {
    testWidgets('点击播放条 → 顶部 toast 显示 4s 后自动消失', (tester) async {
      tts.available = false;
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(
        find.text(ReadingController.ttsErrorMessage),
        findsOneWidget,
      );

      // 4s 后自动清除（对照 Kotlin SnackbarHost + clearSnackbar）
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.text(ReadingController.ttsErrorMessage), findsNothing);
    });
  });

  /// 正文段落的单词（RichText 含内联 WidgetSpan，find.text 精确匹配不到）。
  Finder wordInParagraph(String word) =>
      find.textContaining(word, findRichText: true);

  group('查词弹窗', () {
    testWidgets('点击正文单词 → 先 loading 再回填词头/音标/义项', (tester) async {
      stub.lookupCompleter = Completer<WordDetail?>();
      await pumpScreen(tester);

      await tester.tap(wordInParagraph('Hello'));
      await tester.pump();
      // loading 态
      expect(find.text('正在查询…'), findsOneWidget);

      stub.lookupCompleter!.complete(WordDetail(
        wordId: 10,
        spellingDisplay: 'Hello',
        phoneticIpa: '/həˈləʊ/',
        primarySense: WordSense(
          id: 1,
          orderIndex: 1,
          partOfSpeech: 'interj.',
          chineseMeaning: '你好',
          englishDefinition: 'Used as a greeting.',
          examples: const [],
        ),
        allSenses: [
          WordSense(
            id: 1,
            orderIndex: 1,
            partOfSpeech: 'interj.',
            chineseMeaning: '你好',
            englishDefinition: 'Used as a greeting.',
            examples: const [],
          ),
        ],
      ));
      await tester.pumpAndSettle();
      // 回填态
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('/həˈləʊ/'), findsOneWidget);
      expect(find.text('interj.'), findsOneWidget);
      expect(find.text('Used as a greeting.'), findsOneWidget);
      expect(find.text('你好'), findsOneWidget);
      expect(find.text('加入生词表'), findsOneWidget);
    });

    testWidgets('点击加入生词表 → 按钮变为从生词表移除', (tester) async {
      stub.lookupResult = WordDetail(
        wordId: 10,
        spellingDisplay: 'Hello',
        phoneticIpa: null,
        primarySense: null,
        allSenses: const [],
      );
      stub.addWordEntryId = 99;
      await pumpScreen(tester);

      await tester.tap(wordInParagraph('Hello'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('加入生词表'));
      await tester.pumpAndSettle();

      expect(find.text('从生词表移除'), findsOneWidget);
    });

    testWidgets('关闭 X 关闭弹窗', (tester) async {
      await pumpScreen(tester);

      await tester.tap(wordInParagraph('Hello'));
      await tester.pumpAndSettle();
      expect(find.byType(AppModal), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsNothing);
    });
  });

  group('译文模糊揭示', () {
    Future<void> pumpBlurred(WidgetTester tester) async {
      await pumpScreen(tester);
      // FULL → DIM → BLURRED
      await tester.tap(find.text('完全显示'));
      await tester.pump();
      await tester.tap(find.text('淡化'));
      await tester.pump();
    }

    testWidgets('BLURRED 模式译文模糊；点击揭示后显示明文', (tester) async {
      await pumpBlurred(tester);
      expect(find.byType(ImageFiltered), findsOneWidget);

      await tester.tap(find.text('你好世界。'));
      await tester.pump();

      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.text('你好世界。'), findsOneWidget);
    });

    testWidgets('揭示 10 秒后自动重新模糊', (tester) async {
      await pumpBlurred(tester);

      await tester.tap(find.text('你好世界。'));
      await tester.pump();
      expect(find.byType(ImageFiltered), findsNothing);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.byType(ImageFiltered), findsOneWidget);
    });
  });
}
