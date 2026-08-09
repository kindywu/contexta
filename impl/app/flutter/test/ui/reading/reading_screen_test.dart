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
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

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
  void Function(String? utteranceId, int paragraphIndex, int total)?
      onParagraphStarted;
  String? _lastId;
  void Function(String? utteranceId)? onFinished;

  @override
  bool isAvailable() => available;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0}) {
    if (!available) return null;
    spoken.add(text);
    _lastId = 'ctx-1';
    return 'ctx-1';
  }

  @override
  void stop() {
    stopCount++;
    final id = _lastId;
    _lastId = null;
    onFinished?.call(id);
  }

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {
    onFinished = callback;
  }

  @override
  void setOnParagraphStarted(
      void Function(String? utteranceId, int paragraphIndex, int total)?
          callback) {
    onParagraphStarted = callback;
  }

  void simulateParagraphStarted(int index) {
    onParagraphStarted?.call('ctx-1', index, 2);
  }
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

Article makeLongArticle() => Article(
      id: 2,
      batchId: 1,
      orderIndex: 0,
      contentCategory: 'NEWS',
      title: 'Long Article',
      status: ArticleStatus.success,
      generationStartedAt: null,
      generationCompletedAt: '2026-08-07T12:00:00+08:00',
      retryCount: 0,
      accumulatedReadSeconds: 0,
      readCompletedAt: null,
      lastRetryAt: null,
      paragraphs: [
        for (var i = 0; i < 8; i++)
          ArticleParagraph(
            orderIndex: i,
            englishText:
                'Paragraph $i. This is a fairly long English sentence '
                'used to make each paragraph tall enough to overflow the '
                'test viewport and force scrolling between paragraphs.',
            chineseTranslation: '第 $i 段中文译文。',
          ),
      ],
    );

/// 段落 widget 定位：按 GlobalObjectKey 的 value（内容相等）匹配。
/// GlobalObjectKey 按 identical 判等，跨实例无法用 find.byKey 命中，
/// 故按 key value 过滤。
Finder paragraphFinder(int index) => find.byWidgetPredicate(
      (w) => w.key is GlobalObjectKey &&
          (w.key! as GlobalObjectKey).value == 'reading-para-$index',
    );

/// 段落顶部全局 y（段落未构建（懒构建范围外）时显式失败）。
double paragraphTop(WidgetTester tester, int index) {
  final finder = paragraphFinder(index);
  expect(finder, findsWidgets, reason: '段落 $index 应已构建');
  return tester.getTopLeft(finder).dy;
}

/// 朗读段英文正文 RichText 中带底色的 span 的底色（无底色返回 null）。
/// 页面中 RichText 不止一个（顶栏图标/译文 chip/标题等均为 Text 内部渲染），
/// 需定位到正文段落：其 TextSpan 内含内联播放钮 WidgetSpan，据此筛选。
Color? _firstRichTextBg(WidgetTester tester) {
  final rich = tester.widget<RichText>(
    find.byWidgetPredicate((w) {
      if (w is! RichText) return false;
      final children = (w.text as TextSpan).children;
      return children?.any((s) => s is WidgetSpan) ?? false;
    }).first,
  );
  final spans = (rich.text as TextSpan).children ?? const <InlineSpan>[];
  for (final span in spans) {
    if (span is TextSpan && span.style?.backgroundColor != null) {
      return span.style!.backgroundColor;
    }
  }
  return null;
}

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

  group('屏幕常亮', () {
    testWidgets('进入阅读页开启常亮，退出页面关闭', (tester) async {
      final fake = _FakeWakelock();
      final original = WakelockPlusPlatformInterface.instance;
      WakelockPlusPlatformInterface.instance = fake;
      addTearDown(() {
        WakelockPlusPlatformInterface.instance = original;
      });

      await pumpScreen(tester);
      expect(fake.toggles, [true],
          reason: '进入阅读页应立即开启屏幕常亮');

      await tester.pumpWidget(const SizedBox());
      expect(fake.toggles, [true, false],
          reason: '离开阅读页（dispose）应关闭常亮');
    });
  });

  group('播放条', () {
    testWidgets('常驻底部：播放按钮 + 朗读全文 + 1x 语速胶囊', (tester) async {
      await pumpScreen(tester);

      expect(find.text('朗读全文'), findsOneWidget);
      expect(find.text('1x'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('点击语速胶囊循环切换 1x → 0.8x → 1.2x', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('1x'));
      await tester.pump();
      expect(find.text('0.8x'), findsOneWidget);

      await tester.tap(find.text('0.8x'));
      await tester.pump();
      expect(find.text('1.2x'), findsOneWidget);

      await tester.tap(find.text('1.2x'));
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
    testWidgets('点击标题单词 → 查词弹窗 loading（标题分词可点击）', (tester) async {
      // 单单词标题：tap RichText 中心必落在单词上（多词标题中心可能
      // 落在词间空白，点击不命中任何单词 span）
      stub.article = const Article(
        id: 3,
        batchId: 1,
        orderIndex: 0,
        contentCategory: 'NEWS',
        title: 'Ocean',
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
      stub.lookupCompleter = Completer<WordDetail?>();
      await pumpScreen(tester);

      await tester.tap(find.textContaining('Ocean', findRichText: true));
      await tester.pump();
      expect(find.text('正在查询…'), findsOneWidget);
    });

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

  group('段落朗读高亮', () {
    testWidgets('点击段落播放 → 英文正文加底色；再次点击停止 → 底色消失', (tester) async {
      await pumpScreen(tester);
      expect(_firstRichTextBg(tester), isNull);

      await tester.tap(find.byIcon(Icons.volume_up_outlined));
      await tester.pumpAndSettle();
      expect(_firstRichTextBg(tester), const Color(0x2ECC785C));

      await tester.tap(find.byIcon(Icons.stop_outlined));
      await tester.pumpAndSettle();
      expect(_firstRichTextBg(tester), isNull);
    });

    testWidgets('全文朗读读标题：标题高亮且不滚动；正文第 1 段发声后高亮交接', (tester) async {
      stub.article = makeLongArticle();
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      // 标题段上报 -1：标题文字加底色，段落 0 位置不变（不滚动）
      tts.simulateParagraphStarted(-1);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RichText>(find.text('Long Article', findRichText: true))
            .text
            .style
            ?.backgroundColor,
        const Color(0x2ECC785C),
      );
      final para0Before = paragraphTop(tester, 0);
      await tester.pumpAndSettle();
      expect(paragraphTop(tester, 0), para0Before);

      // 标题段无段号 → 播放条显示「正在朗读…」
      expect(find.text('正在朗读…'), findsOneWidget);

      // 正文第 1 段发声：标题高亮消失 → 段 0 高亮，播放条「第 1/2 段」
      // （播放进度，total 由桩固定为 2）
      tts.simulateParagraphStarted(0);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RichText>(find.text('Long Article', findRichText: true))
            .text
            .style
            ?.backgroundColor,
        isNull,
      );
      expect(_firstRichTextBg(tester), const Color(0x2ECC785C));
      expect(find.text('第 1/2 段'), findsOneWidget);
    });
  });

  group('自动滚动', () {
    testWidgets('全文朗读段落切换 → 滚动到视口 1/3 处', (tester) async {
      stub.article = makeLongArticle();
      await pumpScreen(tester);

      final listViewTop = tester.getTopLeft(find.byType(ListView)).dy;
      final listViewHeight = tester.getSize(find.byType(ListView)).height;
      // 段高 = 相邻段顶部间距（getOffsetToReveal 按 (视口-段高)/3 对齐）
      final paraHeight = paragraphTop(tester, 1) - paragraphTop(tester, 0);

      // 触发全文朗读（走 speak 拼接路径；播放条文字不可点，点播放图标）
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(tts.spoken, isNotEmpty);

      // 段落 0 顶部在 1/3 线上方（首屏内），目标 offset 为负被 clamp，
      // 不做任何滚动
      final para0Before = paragraphTop(tester, 0);
      tts.simulateParagraphStarted(0);
      await tester.pumpAndSettle();
      expect(paragraphTop(tester, 0), para0Before);

      // 切到段落 2 → 段落 2 顶部对齐 (视口-段高)/3 处
      tts.simulateParagraphStarted(2);
      await tester.pumpAndSettle();
      expect(paragraphTop(tester, 2),
          closeTo(listViewTop + (listViewHeight - paraHeight) / 3, 1));
    });

    testWidgets('单段播放不自动滚动', (tester) async {
      stub.article = makeLongArticle();
      await pumpScreen(tester);

      // 先经全文朗读滚动让段 2 可见：段落 0 目标 offset 为负被 clamp，
      // 无法区分门控是否生效；段 2 目标为正——若门控失效会自动滚动 → 红
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      tts.simulateParagraphStarted(1);
      await tester.pumpAndSettle();
      final before = paragraphTop(tester, 2);

      // 点段 2 内联播放（全文播放的滚动是程序滚动，不触发手滚跳过；
      // .first 会命中段 0，须按段落定位）
      await tester.tap(find.descendant(
        of: paragraphFinder(2),
        matching: find.byIcon(Icons.volume_up_outlined),
      ));
      await tester.pumpAndSettle();
      expect(paragraphTop(tester, 2), before);
    });

    testWidgets('用户手动滚动暂停跟随，下一次段落切换恢复', (tester) async {
      stub.article = makeLongArticle();
      await pumpScreen(tester);

      final listViewTop = tester.getTopLeft(find.byType(ListView)).dy;
      final listViewHeight = tester.getSize(find.byType(ListView)).height;
      final paraHeight = paragraphTop(tester, 1) - paragraphTop(tester, 0);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      tts.simulateParagraphStarted(0);
      await tester.pumpAndSettle();

      // 用户上滑离开当前段（-200：保证段落 1 仍在构建范围内）
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      final afterDrag = paragraphTop(tester, 1);

      // 段落 1 切换：被手滚跳过（位置不变）
      tts.simulateParagraphStarted(1);
      await tester.pumpAndSettle();
      final duringUserScroll = paragraphTop(tester, 1);
      expect(duringUserScroll, closeTo(afterDrag, 1));

      // 段落 2 切换：恢复跟随
      tts.simulateParagraphStarted(2);
      await tester.pumpAndSettle();
      expect(paragraphTop(tester, 2),
          closeTo(listViewTop + (listViewHeight - paraHeight) / 3, 1));
      expect(paragraphTop(tester, 1), isNot(closeTo(duringUserScroll, 1)));
    });

    testWidgets('段落未构建（懒加载范围外）→ 估算定位兜底', (tester) async {
      stub.article = makeLongArticle();
      await pumpScreen(tester);

      // 触发全文朗读
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(tts.spoken, isNotEmpty);

      final position = tester
          .state<ScrollableState>(find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ))
          .position;
      // 滚动前快照 maxScrollExtent：SliverList 对未构建尾部按均值估算，
      // 滚动后尾部已构建该值会变化——须与兜底实现同一时刻读取
      final maxBefore = position.maxScrollExtent;

      // 大幅跳转到段 6：超出首屏 viewport + cacheExtent 构建范围，
      // currentContext 为 null → 估算兜底（maxScrollExtent * 6/8），不抛错
      tts.simulateParagraphStarted(6);
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(0));
      expect(position.pixels, closeTo(maxBefore * 6 / 8, 1));
    });
  });
}

/// 屏幕常亮 fake：记录 toggle 调用序列（替换 platform instance，绕开
/// pigeon MethodChannel，测试无需 mock 通道编码）。
class _FakeWakelock extends WakelockPlusPlatformInterface {
  final List<bool> toggles = [];

  @override
  Future<void> toggle({required bool enable}) async {
    toggles.add(enable);
  }

  @override
  Future<bool> get enabled async => toggles.isNotEmpty && toggles.last;
}
