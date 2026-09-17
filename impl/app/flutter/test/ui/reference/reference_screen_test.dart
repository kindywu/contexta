import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/reference/reference_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference 页 widget 测试（Task 28）。
/// 数据完整性已由 reference_data_test 覆盖，此处验证 UI 接线：
/// - tabs 切换（字母表 / 音标 / 语法）
/// - 字母格 / 音标格点击 → 弹窗内容（大字 / 音标 / 例词 / 发音按钮）
/// - 弹窗发音：大字读 own sound，发音按钮读 speak 文本
/// - 语法折叠展开（默认展开第一组，可折叠 / 展开）
/// - 路由接线（app_router_test 覆盖）

class _TtsStub implements TtsEngine {
  final List<String> spoken = [];

  @override
  bool isAvailable() => true;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
    spoken.add(text);
    return 'ctx-1';
  }

  @override
  void stop() {}

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {}

  @override
  void setOnSentenceStarted(
      void Function(String? utteranceId, int paragraphIndex, int sentenceIndex,
              int total)?
          callback) {}
}

void main() {
  late _TtsStub tts;

  setUp(() {
    tts = _TtsStub();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ttsEngineProvider.overrideWith((ref) async => tts),
      ],
      child: const MaterialApp(home: ReferenceScreen()),
    ));
    await tester.pumpAndSettle();
  }

  group('tabs 切换', () {
    testWidgets('默认字母表；切到音标 / 语法', (tester) async {
      await pumpScreen(tester);

      expect(find.text('字母表'), findsOneWidget);
      expect(find.text('A a'), findsOneWidget);
      expect(find.text('Apple'), findsNothing); // 例词在弹窗中

      await tester.tap(find.text('音标'));
      await tester.pumpAndSettle();
      expect(find.text('单元音 (12)'), findsOneWidget);
      expect(find.text('/iː/'), findsOneWidget);

      await tester.tap(find.text('语法'));
      await tester.pumpAndSettle();
      expect(find.text('时态'), findsOneWidget);
      expect(find.text('一般现在时 (Present Simple)'), findsOneWidget);
    });
  });

  group('字母格弹窗', () {
    testWidgets('点击字母格 → 弹窗展示大字/音标/例词/发音按钮', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('A a'));
      await tester.pumpAndSettle();

      expect(find.text('A a'), findsNWidgets(2)); // 格子 + 弹窗大字
      expect(find.text('/eɪ/'), findsNWidgets(2)); // 格子 + 弹窗音标
      expect(find.text('Apple'), findsOneWidget);
      expect(find.text('苹果'), findsOneWidget);
      expect(find.text('发音'), findsOneWidget);

      // 发音按钮：字母名 + 例词
      await tester.tap(find.text('发音'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['A. Apple']);
    });

    testWidgets('弹窗大字点击 → 读字母名', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('A a'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A a').last); // 弹窗中的大字
      await tester.pumpAndSettle();
      expect(tts.spoken, ['A']);

      // 例词点击 → 读例词
      await tester.tap(find.text('Apple'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['A', 'Apple']);
    });

    testWidgets('关闭按钮关闭弹窗', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('A a'));
      await tester.pumpAndSettle();
      expect(find.text('发音'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('发音'), findsNothing);
    });
  });

  group('音标格弹窗', () {
    testWidgets('点击音标格 → 分类名 + 例词 + 发音读例词', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('音标'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/iː/').first);
      await tester.pumpAndSettle();

      // 弹窗：分类名（Muted 正文）+ 例词 see（珊瑚）
      // 'see' 出现 2 次：网格格子 + 弹窗例词
      expect(find.text('单元音 (12)'), findsNWidgets(2)); // 分组头 + 弹窗
      expect(find.text('see'), findsNWidgets(2));
      expect(find.text('发音'), findsOneWidget);

      await tester.tap(find.text('发音'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['see']);
    });

    testWidgets('音标大字点击 → 读自身拟音', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('音标'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/iː/').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('/iː/').last); // 弹窗大字
      await tester.pumpAndSettle();
      expect(tts.spoken, ['ee']);
    });
  });

  group('大屏列数', () {
    testWidgets('pad 横屏字母表一行 8 个格子', (tester) async {
      tester.view.physicalSize = const Size(2438, 1626); // 逻辑 1219×813
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpScreen(tester);

      // 前 8 个字母同一行：'A a' 与 'H h' 顶边相同，'I i' 换行
      final a = tester.getTopLeft(find.text('A a'));
      final h = tester.getTopLeft(find.text('H h'));
      final i = tester.getTopLeft(find.text('I i'));
      expect(h.dy, a.dy);
      expect(i.dy, greaterThan(a.dy));
    });

    testWidgets('手机字母表仍是 4 列', (tester) async {
      await pumpScreen(tester); // 默认窗口 800×600 = medium
      final a = tester.getTopLeft(find.text('A a'));
      final d = tester.getTopLeft(find.text('D d'));
      final e = tester.getTopLeft(find.text('E e'));
      expect(d.dy, a.dy);
      expect(e.dy, greaterThan(a.dy));
    });

    testWidgets('手机末行格子不被拉伸（与整行同宽）', (tester) async {
      // 26 字母 = 6×4 + 2：既有实现给末行补空 Expanded，格子仍是 1/4 宽。
      // 这条锁住手机渲染不变（列数改造不许把末行拉成半宽）。
      await pumpScreen(tester); // 默认窗口 800×600 = medium
      final a = tester.getCenter(find.text('A a'));
      final b = tester.getCenter(find.text('B b'));
      final y = tester.getCenter(find.text('Y y'));
      final z = tester.getCenter(find.text('Z z'));
      expect(y.dy, greaterThan(a.dy), reason: 'Y 在末行');
      expect(z.dx - y.dx, b.dx - a.dx, reason: '末行格子间距与整行一致');
    });

    testWidgets('pad 横屏音标一行 6 个格子', (tester) async {
      tester.view.physicalSize = const Size(2438, 1626);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpScreen(tester);

      await tester.tap(find.text('音标'));
      await tester.pumpAndSettle();

      // 单元音组第一行 6 格：/iː/ /ɪ/ /e/ /æ/ /ɑː/ /ɒ/，第 7 格换行
      final first = tester.getTopLeft(find.text('/iː/'));
      final sixth = tester.getTopLeft(find.text('/ɒ/'));
      final seventh = tester.getTopLeft(find.text('/ɔː/'));
      expect(sixth.dy, first.dy);
      expect(seventh.dy, greaterThan(first.dy));
    });
  });

  group('语法折叠', () {
    testWidgets('默认展开第一组，点击分组头折叠/展开', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('语法'));
      await tester.pumpAndSettle();

      // 默认展开：第一组条目可见
      expect(find.text('一般现在时 (Present Simple)'), findsOneWidget);

      // 折叠第一组
      await tester.tap(find.text('时态'));
      await tester.pumpAndSettle();
      expect(find.text('一般现在时 (Present Simple)'), findsNothing);

      // 重新展开
      await tester.tap(find.text('时态'));
      await tester.pumpAndSettle();
      expect(find.text('一般现在时 (Present Simple)'), findsOneWidget);
    });

    testWidgets('第二组默认折叠，点击展开', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('语法'));
      await tester.pumpAndSettle();

      expect(find.text('名词复数 (Plural Nouns)'), findsNothing);

      // 第二组 header 在视口外：先滚动到可见再点击
      await tester.ensureVisible(find.text('词形变化'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('词形变化'));
      await tester.pumpAndSettle();
      expect(find.text('名词复数 (Plural Nouns)'), findsOneWidget);
    });
  });
}
