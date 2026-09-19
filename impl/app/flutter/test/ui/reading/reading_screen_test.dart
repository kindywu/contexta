import 'dart:async';

import 'package:contexta/core/components/app_modal.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/data/remote/llm_api.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/tts_voice.dart';
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
import 'package:contexta/ui/reading/sentence_extractor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
class _Stub
    implements
        ArticleRepository,
        SettingsRepository,
        VocabularyRepository,
        StatsRepository,
        WordRepository,
        LlmApi {
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
    String spelling,
    Future<WordDetail?> Function(String) llmFallback,
  ) {
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
  void Function(String? utteranceId, int paragraphIndex, int sentenceIndex,
      int total)? onSentenceStarted;
  String? _lastId;
  void Function(String? utteranceId)? onFinished;

  @override
  bool isAvailable() => available;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
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
  void setOnSentenceStarted(
    void Function(String? utteranceId, int paragraphId, int sentenceIndex,
            int total)?
        callback,
  ) {
    onSentenceStarted = callback;
  }

  /// 模拟 [paragraphId] 段第 [sentenceIndex] 句开始发声（总句数默认 2）。
  ///
  /// 传的是**段落 id**——引擎的真实契约（原样回传朗读单元的
  /// `SentenceUnit.paragraphId`），不是段落序号；夹具里的段落 id 见
  /// [makeLongArticle] / [makeSentenceScrollArticle]。
  void simulateSentenceStarted(int paragraphId, int sentenceIndex,
      {int total = 2}) {
    onSentenceStarted?.call('ctx-1', paragraphId, sentenceIndex, total);
  }
}

Article makeArticle() => const Article(
  id: 1,
  batchId: 1,
  orderIndex: 0,
  contentCategory: 'NEWS',
  title: 'A Day',
  status: ArticleStatus.success,
  accumulatedReadSeconds: 0,
  readCompletedAt: null,
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
  accumulatedReadSeconds: 0,
  readCompletedAt: null,
  paragraphs: [
    // id 非 0 且不等于序号：生产库里 article_paragraph.id 是全局自增
    // （实测 727 起），引擎按 id 上报播放位置——夹具若用默认的 0，
    // 「id 恰好等于序号」会让忘了换算的 bug 在测试里隐形。
    for (var i = 0; i < 8; i++)
      ArticleParagraph(
        id: 100 + i,
        orderIndex: i,
        englishText:
            'Paragraph $i. This is a fairly long English sentence '
            'used to make each paragraph tall enough to overflow the '
            'test viewport and force scrolling between paragraphs.',
        chineseTranslation: '第 $i 段中文译文。',
      ),
  ],
);

/// 长文（12 段，第 5 段首句跨行）：其余段各一句占位，保证列表可滚动且
/// 第 5 段在首屏内——用于验证按句滚动的句内偏移（句 1 首行不在段落顶部）。
Article makeSentenceScrollArticle() => Article(
  id: 3,
  batchId: 1,
  orderIndex: 0,
  contentCategory: 'NEWS',
  title: 'Scroll',
  status: ArticleStatus.success,
  accumulatedReadSeconds: 0,
  readCompletedAt: null,
  paragraphs: [
    // 24 段而不是 12：待验证的段 5 后面必须有足够内容，否则「句首行对齐视口
    // 1/3」的目标 offset 会超过 maxScrollExtent 被 clamp，断言量到的是滚动
    // 上限而不是对齐规则（正文 22sp 后段落变高，12 段已不够）。
    for (var i = 0; i < 24; i++)
      if (i == 5)
        const ArticleParagraph(
          id: 205,
          orderIndex: 5,
          englishText:
              'Alpha bravo charlie delta echo foxtrot golf hotel india juliet '
              'kilo lima mike november oscar papa quebec romeo. '
              'Second sentence starts on a later line and keeps going so the '
              'paragraph wraps across several lines in the test viewport.',
          chineseTranslation: '第五段。',
        )
      else
        ArticleParagraph(
          id: 200 + i,
          orderIndex: i,
          englishText: 'Paragraph $i.',
          chineseTranslation: '第 $i 段。',
        ),
  ],
);

/// 段落 widget 定位：按 GlobalObjectKey 的 value（内容相等）匹配。
/// GlobalObjectKey 按 identical 判等，跨实例无法用 find.byKey 命中，
/// 故按 key value 过滤。
Finder paragraphFinder(int index) => find.byWidgetPredicate(
  (w) =>
      w.key is GlobalObjectKey &&
      (w.key! as GlobalObjectKey).value == 'reading-para-$index',
);

/// 段落顶部全局 y（段落未构建（懒构建范围外）时显式失败）。
double paragraphTop(WidgetTester tester, int index) {
  final finder = paragraphFinder(index);
  expect(finder, findsWidgets, reason: '段落 $index 应已构建');
  return tester.getTopLeft(finder).dy;
}

/// 把测试视口换成 800×1400 的高视口。
///
/// 默认测试视口 800×600 太矮：正文 22sp 后段落块高约 239（默认视口下近乎占满），
/// 「段落顶部在 1/3 线上方 → 目标 offset 为负被 clamp」与「靠后的段落已构建」
/// 这两个几何前提都不再成立。拉高视口是为了让这些用例继续验证真实规则，而不是
/// 放宽断言——真机（411×731，视口约 600dp）上短段落走的就是这些分支。
void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

/// 段落英文正文 RichText（按 ReadingScreen 的 textKey 定位）。
Finder paragraphTextFinder(int index) => find.byWidgetPredicate(
  (w) =>
      w is RichText &&
      w.key is GlobalObjectKey &&
      (w.key! as GlobalObjectKey).value == 'reading-para-text-$index',
);

/// 段落英文正文里带底色的文字段（相邻同底色 span 合并；用于断言「只高亮
/// 当前句」）。
List<String> highlightedTexts(WidgetTester tester, int index) {
  final rich = tester.widget<RichText>(paragraphTextFinder(index));
  final spans = (rich.text as TextSpan).children ?? const <InlineSpan>[];
  final out = <String>[];
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isNotEmpty) {
      out.add(buffer.toString());
      buffer.clear();
    }
  }

  for (final span in spans) {
    if (span is TextSpan && span.style?.backgroundColor != null) {
      buffer.write(span.text ?? '');
    } else {
      flush();
    }
  }
  flush();
  return out;
}

/// 段落英文正文里第 [sentenceIndex] 句首行相对该段首行的 y 偏移（按句滚动
/// 的句内偏移量；测试内独立求值，不复用实现）。
double sentenceBoxTopIn(
  WidgetTester tester,
  int paragraphIndex,
  int sentenceIndex,
) {
  final render = tester.renderObject<RenderParagraph>(
    paragraphTextFinder(paragraphIndex),
  );
  final ranges = findSentenceRanges(render.text.toPlainText());
  final (start, end) = ranges[sentenceIndex];
  final boxes = render.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
  );
  final firstBoxes = render.getBoxesForSelection(
    const TextSelection(baseOffset: 0, extentOffset: 1),
  );
  return boxes.first.top - firstBoxes.first.top;
}

void main() {
  late _Stub stub;
  late _TtsStub tts;

  setUp(() {
    stub = _Stub()..article = makeArticle();
    tts = _TtsStub();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          articleRepositoryProvider.overrideWithValue(stub),
          settingsRepositoryProvider.overrideWithValue(stub),
          vocabularyRepositoryProvider.overrideWithValue(stub),
          statsRepositoryProvider.overrideWithValue(stub),
          wordRepositoryProvider.overrideWithValue(stub),
          llmApiProvider.overrideWithValue(stub),
          ttsEngineProvider.overrideWith((ref) async => tts),
        ],
        child: MaterialApp(home: ReadingScreen(articleId: 1, onBack: () {})),
      ),
    );
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
      expect(fake.toggles, [true], reason: '进入阅读页应立即开启屏幕常亮');

      await tester.pumpWidget(const SizedBox());
      expect(fake.toggles, [true, false], reason: '离开阅读页（dispose）应关闭常亮');
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
      expect(find.text(ReadingController.ttsErrorMessage), findsOneWidget);

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
        accumulatedReadSeconds: 0,
        readCompletedAt: null,
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

      stub.lookupCompleter!.complete(
        WordDetail(
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
        ),
      );
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

    testWidgets('义项过多时弹窗可滚动，最后的义项可滚入视窗', (tester) async {
      // 25 个义项使内容总高远超 AppModal 的 75% 屏高上限（600px 视口 → 450px），
      // 弹窗内容必须可滚动，否则长义项被裁切且无法滚到。
      stub.lookupResult = WordDetail(
        wordId: 10,
        spellingDisplay: 'Hello',
        phoneticIpa: '/həˈləʊ/',
        primarySense: null,
        allSenses: [
          for (var i = 0; i < 25; i++)
            WordSense(
              id: i + 1,
              orderIndex: i + 1,
              partOfSpeech: i.isEven ? 'n.' : 'v.',
              chineseMeaning: '释义 $i',
              englishDefinition:
                  'Sense definition $i, deliberately long enough to make '
                  'the sheet taller than the modal maximum height.',
              examples: const [],
            ),
        ],
      );
      await pumpScreen(tester);

      await tester.tap(wordInParagraph('Hello'));
      await tester.pumpAndSettle();

      // 弹窗内容必须包在可滚动容器中（否则长义项被 75% 屏高裁切）
      final modalScrollable = find.descendant(
        of: find.byType(AppModal),
        matching: find.byType(SingleChildScrollView),
      );
      expect(modalScrollable, findsOneWidget);

      // fling 滚到底后，内容末尾的「加入生词表」按钮完整进入视窗
      // （修复前按钮被裁切在溢出区，不可见也不可点）
      await tester.fling(modalScrollable, const Offset(0, -1200), 3000);
      await tester.pumpAndSettle();
      final addButton = find.text('加入生词表');
      expect(addButton, findsOneWidget);
      final rect = tester.getRect(addButton);
      expect(rect.bottom, lessThanOrEqualTo(600.0), reason: '按钮应完整在视窗内');
      expect(rect.top, greaterThanOrEqualTo(0));
    });

    testWidgets('长内容弹窗的关闭按钮固定在顶部，不随滚动移动', (tester) async {
      stub.lookupResult = WordDetail(
        wordId: 10,
        spellingDisplay: 'Hello',
        phoneticIpa: '/həˈləʊ/',
        primarySense: null,
        allSenses: [
          for (var i = 0; i < 25; i++)
            WordSense(
              id: i + 1,
              orderIndex: i + 1,
              partOfSpeech: i.isEven ? 'n.' : 'v.',
              chineseMeaning: '释义 $i',
              englishDefinition:
                  'Sense definition $i, deliberately long enough to make '
                  'the sheet taller than the modal maximum height.',
              examples: const [],
            ),
        ],
      );
      await pumpScreen(tester);

      await tester.tap(wordInParagraph('Hello'));
      await tester.pumpAndSettle();

      final closeBtn = find.byIcon(Icons.close);
      final before = tester.getTopLeft(closeBtn);

      final scrollable = find.descendant(
        of: find.byType(AppModal),
        matching: find.byType(SingleChildScrollView),
      );
      await tester.fling(scrollable, const Offset(0, -1200), 3000);
      await tester.pumpAndSettle();

      final after = tester.getTopLeft(closeBtn);
      expect(after.dy, closeTo(before.dy, 0.1), reason: '关闭按钮应固定置顶，不随内容滚动');
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

  group('句子朗读高亮', () {
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

    testWidgets('句子回调只高亮当前句（不是整段）', (tester) async {
      stub.article = makeLongArticle();
      await pumpScreen(tester);

      // 全文朗读（走 speak 拼接路径；播放条文字不可点，点播放图标）
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      // 段 0 第 1 句（"Paragraph 0."）发声：只有该句带底色
      tts.simulateSentenceStarted(100, 0, total: 16);
      await tester.pumpAndSettle();
      expect(highlightedTexts(tester, 0), ['Paragraph 0.']);

      // 段 0 第 2 句发声：底色移到第 2 句
      tts.simulateSentenceStarted(100, 1, total: 16);
      await tester.pumpAndSettle();
      final second = highlightedTexts(tester, 0);
      expect(second, hasLength(1));
      expect(second.single, startsWith('This is a fairly long English sentence'));
    });

    testWidgets('全文朗读读标题：标题高亮且不滚动；正文第 1 句发声后高亮交接', (tester) async {
      stub.article = makeLongArticle();
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      // 标题上报 -1：标题文字加底色，段落 0 位置不变（不滚动）
      tts.simulateSentenceStarted(-1, 0);
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

      // 标题无句号 → 播放条显示「正在朗读…」
      expect(find.text('正在朗读…'), findsOneWidget);

      // 正文第 1 句发声：标题高亮消失 → 段 0 首句高亮，播放条「第 1/16 句」
      tts.simulateSentenceStarted(100, 0, total: 16);
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
      expect(find.text('第 1/16 句'), findsOneWidget);
    });
  });

  group('自动滚动', () {
    testWidgets('全文朗读段落切换 → 滚动到视口 1/3 处', (tester) async {
      useTallViewport(tester);
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
      tts.simulateSentenceStarted(100, 0);
      await tester.pumpAndSettle();
      expect(paragraphTop(tester, 0), para0Before);

      // 切到段落 2 → 段落 2 顶部对齐 (视口-段高)/3 处
      tts.simulateSentenceStarted(102, 0);
      await tester.pumpAndSettle();
      expect(
        paragraphTop(tester, 2),
        closeTo(listViewTop + (listViewHeight - paraHeight) / 3, 1),
      );
    });

    testWidgets('单段播放不自动滚动', (tester) async {
      stub.article = makeLongArticle();
      await pumpScreen(tester);

      // 先经全文朗读滚动让段 2 可见：段落 0 目标 offset 为负被 clamp，
      // 无法区分门控是否生效；段 2 目标为正——若门控失效会自动滚动 → 红
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      tts.simulateSentenceStarted(101, 0);
      await tester.pumpAndSettle();
      final before = paragraphTop(tester, 2);

      // 点段 2 内联播放（全文播放的滚动是程序滚动，不触发手滚跳过；
      // .first 会命中段 0，须按段落定位）
      await tester.tap(
        find.descendant(
          of: paragraphFinder(2),
          matching: find.byIcon(Icons.volume_up_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(paragraphTop(tester, 2), before);
    });

    testWidgets('按句滚动：当前句首行对齐视口 1/3（句内偏移叠加）', (tester) async {
      useTallViewport(tester);
      stub.article = makeSentenceScrollArticle();
      await pumpScreen(tester);

      final listViewTop = tester.getTopLeft(find.byType(ListView)).dy;
      final listViewHeight = tester.getSize(find.byType(ListView)).height;
      final paraHeight = tester.getSize(paragraphFinder(5)).height;

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      // 段 5 句 1 发声：句 1 首行（非段落顶部）对齐 1/3 线
      final boxTop = sentenceBoxTopIn(tester, 5, 1);
      expect(boxTop, greaterThan(0), reason: '句 1 应从第二行起，否则本用例无意义');
      tts.simulateSentenceStarted(205, 1);
      await tester.pumpAndSettle();

      expect(
        paragraphTop(tester, 5),
        closeTo(listViewTop + (listViewHeight - paraHeight) / 3 - boxTop, 1),
      );
    });

    testWidgets('用户手动滚动暂停跟随，下一次段落切换恢复', (tester) async {
      stub.article = makeLongArticle();
      await pumpScreen(tester);

      final listViewTop = tester.getTopLeft(find.byType(ListView)).dy;
      final listViewHeight = tester.getSize(find.byType(ListView)).height;
      final paraHeight = paragraphTop(tester, 1) - paragraphTop(tester, 0);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      tts.simulateSentenceStarted(100, 0);
      await tester.pumpAndSettle();

      // 用户上滑离开当前段（-200：保证段落 1 仍在构建范围内）
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      final afterDrag = paragraphTop(tester, 1);

      // 段落 1 切换：被手滚跳过（位置不变）
      tts.simulateSentenceStarted(101, 0);
      await tester.pumpAndSettle();
      final duringUserScroll = paragraphTop(tester, 1);
      expect(duringUserScroll, closeTo(afterDrag, 1));

      // 段落 2 切换：恢复跟随
      tts.simulateSentenceStarted(102, 0);
      await tester.pumpAndSettle();
      expect(
        paragraphTop(tester, 2),
        closeTo(listViewTop + (listViewHeight - paraHeight) / 3, 1),
      );
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
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      // 滚动前快照 maxScrollExtent：SliverList 对未构建尾部按均值估算，
      // 滚动后尾部已构建该值会变化——须与兜底实现同一时刻读取
      final maxBefore = position.maxScrollExtent;

      // 大幅跳转到段 6：超出首屏 viewport + cacheExtent 构建范围，
      // currentContext 为 null → 估算兜底（maxScrollExtent * 6/8），不抛错
      tts.simulateSentenceStarted(106, 0);
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
