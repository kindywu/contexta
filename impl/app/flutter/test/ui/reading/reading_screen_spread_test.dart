import 'dart:async';

import 'package:contexta/data/remote/llm_api.dart';
import 'package:contexta/di/providers.dart';
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
import 'package:contexta/ui/reading/reading_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading 页书页模式（pad 横屏）接线测试：窗口宽度分支 + 分页 + 跨页进度。
///
/// 手机 / pad 竖屏路径的完整回归在 reading_screen_test.dart（本文件只覆盖
/// expanded 档新增的书页分支；两个文件各自独立，不共享 part）。
///
/// 默认测试窗口 800×600 逻辑像素 = medium 档 → 手机路径，必须显式改
/// `tester.view.physicalSize` 才能进入 expanded（宽 ≥ 840）。

/// 组合桩：实现 Reading 页依赖的全部仓储/客户端接口。
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

  /// 非 null 时 lookupWord 挂起，由测试手动 complete。
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

/// TTS 桩：本文件只需要一个能装配的引擎。
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
    void Function(String? utteranceId, int paragraphIndex, int sentenceIndex,
            int total)?
        callback,
  ) {
    onSentenceStarted = callback;
  }

  /// 模拟第 [paragraphIndex] 段第 [sentenceIndex] 句开始发声（总句数默认 2）。
  void simulateSentenceStarted(int paragraphIndex, int sentenceIndex,
      {int total = 2}) {
    onSentenceStarted?.call('ctx-1', paragraphIndex, sentenceIndex, total);
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

/// 多页文章：段落足够多，pad 横屏下一页装不下——用于「翻遍全部跨页」与
/// 进度条推进两个用例（单段文章只有一跨页，翻页/进度断言会退化为空转）。
Article makePagedArticle() => Article(
  id: 2,
  batchId: 1,
  orderIndex: 0,
  contentCategory: 'NEWS',
  title: 'A Long Day',
  status: ArticleStatus.success,
  accumulatedReadSeconds: 0,
  readCompletedAt: null,
  paragraphs: [
    for (var i = 0; i < 40; i++)
      ArticleParagraph(
        orderIndex: i,
        englishText:
            'Paragraph $i. This is a fairly long English sentence used to '
            'make each paragraph tall enough that the paginator has to break '
            'the article across several pages in the test viewport.',
        chineseTranslation: '第 $i 段中文译文。',
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

/// pad 横屏：逻辑 1219×813（物理 2438×1626 @2x）。
void setPadLandscape(WidgetTester tester) {
  tester.view.physicalSize = const Size(2438, 1626);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// pad 竖屏：逻辑 813×1219。
void setPadPortrait(WidgetTester tester) {
  tester.view.physicalSize = const Size(1626, 2438);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 手机：逻辑 1080×2340 @3x = 360×780。
void setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 当前书页模式的总跨页数（PageView 的 itemCount）。
int spreadCount(WidgetTester tester) {
  final pageView = tester.widget<PageView>(find.byType(PageView));
  final delegate = pageView.childrenDelegate as SliverChildBuilderDelegate;
  return delegate.childCount ?? 0;
}

/// 当前 PageView 的跨页序号。
int currentSpread(WidgetTester tester) => tester
    .widget<PageView>(find.byType(PageView))
    .controller!
    .page!
    .round();

void main() {
  late _Stub stub;
  late _TtsStub tts;

  setUp(() {
    stub = _Stub()..article = makeArticle();
    tts = _TtsStub();
  });

  /// 按不同窗口尺寸渲染阅读页（手机路径的 `pumpScreen` 同款 override）。
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

  testWidgets('pad 横屏进入书页模式（有 PageView，无 ListView）', (tester) async {
    setPadLandscape(tester);
    await pumpScreen(tester);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('手机宽度仍是单列列表（无 PageView）', (tester) async {
    setPhone(tester);
    await pumpScreen(tester);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('pad 竖屏（813dp 宽）仍是单列列表', (tester) async {
    setPadPortrait(tester);
    await pumpScreen(tester);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('pad 横屏书页不溢出页底（页高已扣掉页码行与页内留白）', (tester) async {
    stub.article = makePagedArticle();
    setPadLandscape(tester);
    await pumpScreen(tester);

    // 页高算大 → 分页器往页里塞过多内容 → 书页里的 Column 溢出
    // （RenderFlex overflow 会以异常形式冒出来）
    expect(tester.takeException(), isNull);
    expect(spreadCount(tester), greaterThan(1), reason: '多页文章应产生多个跨页');
  });

  testWidgets('翻遍全部跨页后每段都出现过（分页不丢块）', (tester) async {
    stub.article = makePagedArticle();
    setPadLandscape(tester);
    await pumpScreen(tester);

    final total = makePagedArticle().paragraphs.length;
    final spreads = spreadCount(tester);
    expect(spreads, greaterThan(1), reason: '单跨页测不出翻页丢失，用例前提不成立');

    final seen = <int>{};
    for (var spread = 0; spread < spreads; spread++) {
      for (var i = 0; i < total; i++) {
        if (paragraphFinder(i).evaluate().isNotEmpty) seen.add(i);
      }
      if (spread == spreads - 1) break;
      await tester.drag(find.byType(PageView), const Offset(-800, 0));
      await tester.pumpAndSettle();
    }
    expect(seen.length, total, reason: '每段都应能在某一跨页上找到');
  });

  testWidgets('书页模式进度条随跨页推进', (tester) async {
    stub.article = makePagedArticle();
    setPadLandscape(tester);
    await pumpScreen(tester);

    final bar = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxHeight == 3,
    );
    expect(bar, findsOneWidget);
    final before = tester.getSize(bar).width;
    expect(before, greaterThan(0));

    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(bar).width, greaterThan(before));
  });

  testWidgets('pad 横屏书页内译文切换与点击揭示照常生效（切换触发重排）', (tester) async {
    setPadLandscape(tester);
    await pumpScreen(tester);

    // FULL → DIM → BLURRED：译文模式在分页 memo 里，每次切换都会重排
    await tester.tap(find.text('完全显示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('淡化'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 点击译文揭示（书页分支的 onTranslationClick 已接线）
    await tester.tap(find.text('你好世界。'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.text('你好世界。'), findsOneWidget);
  });

  testWidgets('pad 横屏书页内「标记已读」生效（未读块消失 → 顶栏显示已读）', (tester) async {
    setPadLandscape(tester);
    await pumpScreen(tester);
    expect(find.text('标记已读'), findsOneWidget);

    await tester.tap(find.text('标记已读'));
    await tester.pumpAndSettle();

    expect(find.text('✓ 已读'), findsOneWidget);
    expect(find.text('标记已读'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('朗读自动翻页', () {
    testWidgets('全文朗读跨页时自动翻到目标跨页', (tester) async {
      stub.article = makePagedArticle();
      setPadLandscape(tester);
      await pumpScreen(tester);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(currentSpread(tester), 0);

      // 报到最后一段（多段文章里必不在第 1 跨页）
      final last = makePagedArticle().paragraphs.length - 1;
      tts.simulateSentenceStarted(last, 0, total: 2);
      await tester.pumpAndSettle();

      expect(currentSpread(tester), greaterThan(0), reason: '朗读跨页应自动翻页');
      expect(paragraphFinder(last), findsWidgets, reason: '应翻到含目标段的跨页');
    });

    testWidgets('用户刚手动翻页时跳过一次自动翻页', (tester) async {
      stub.article = makePagedArticle();
      setPadLandscape(tester);
      await pumpScreen(tester);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-800, 0));
      await tester.pumpAndSettle();
      final afterDrag = currentSpread(tester);
      expect(afterDrag, greaterThan(0), reason: '手拖应真的翻过去，否则用例无意义');

      // 目标句在第 1 页（第 0 跨页）——若不被跳过就会翻回去
      tts.simulateSentenceStarted(0, 0, total: 2);
      await tester.pumpAndSettle();

      expect(currentSpread(tester), afterDrag, reason: '手刚拖过，本次不自动翻');

      // 跳过一次即恢复跟随（不是永久停用）
      tts.simulateSentenceStarted(0, 1, total: 2);
      await tester.pumpAndSettle();
      expect(currentSpread(tester), 0, reason: '下一次句子切换应恢复跟随');
    });

    testWidgets('页边点击翻页同样跳过一次自动翻页', (tester) async {
      stub.article = makePagedArticle();
      setPadLandscape(tester);
      await pumpScreen(tester);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      // 点右侧页边翻页：pad 横屏 1219 宽 → 页边条 (1219 − 1100) / 2 = 59.5
      // ≥ kEdgeTapMinWidth(24)，页边点击可用；点右侧条内靠窗边处
      final pageView = tester.getRect(find.byType(PageView));
      await tester.tapAt(Offset(pageView.right - 10, pageView.center.dy));
      await tester.pumpAndSettle();
      final afterTap = currentSpread(tester);
      expect(afterTap, greaterThan(0), reason: '点页边应真的翻过去，否则用例无意义');

      // 目标句在第 1 页（第 0 跨页）——若不被跳过就会翻回去
      tts.simulateSentenceStarted(0, 0, total: 2);
      await tester.pumpAndSettle();
      expect(currentSpread(tester), afterTap, reason: '页边刚翻过，本次不自动翻');

      // 跳过一次即恢复跟随（与拖拽同款语义）
      tts.simulateSentenceStarted(0, 1, total: 2);
      await tester.pumpAndSettle();
      expect(currentSpread(tester), 0, reason: '下一次句子切换应恢复跟随');
    });

    testWidgets('单段播放不触发自动翻页', (tester) async {
      stub.article = makePagedArticle();
      setPadLandscape(tester);
      await pumpScreen(tester);

      // 不点全文播放，直接点第 1 段的内联播放钮（书页内按段落定位）
      await tester.tap(
        find.descendant(
          of: paragraphFinder(0),
          matching: find.byIcon(Icons.volume_up_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentSpread(tester), 0);

      final last = makePagedArticle().paragraphs.length - 1;
      tts.simulateSentenceStarted(last, 0, total: 2);
      await tester.pumpAndSettle();

      expect(currentSpread(tester), 0, reason: '单段播放只高亮不翻页（与手机一致）');
    });
  });
}
