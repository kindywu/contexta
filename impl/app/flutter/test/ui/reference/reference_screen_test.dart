import 'package:contexta/core/theme/app_colors.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/audio/phoneme_audio.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/reference/reference_controller.dart';
import 'package:contexta/ui/reference/reference_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference 页 widget 测试（Task 28）。
/// 数据完整性已由 reference_data_test 覆盖，此处验证 UI 接线：
/// - tabs 切换（字母表 / 音标 / 语法）
/// - 字母格 / 音标格点击 → 弹窗内容（符号位 / 注脚 / 例词 / 拼写行 / 发音按钮）
/// - 弹窗发音：字母格走 TTS，音标格走随包录音（不走 TTS）
/// - 语法折叠展开（默认展开第一组，可折叠 / 展开）
/// - 路由接线（app_router_test 覆盖）

/// 假录音库：记录播放过哪些音标（widget 测试里不碰真实 audioplayers）。
class _AudioStub implements PhonemeAudio {
  final List<String> played = [];

  @override
  Future<bool> play(String phone) async {
    played.add(phone);
    return true;
  }
}

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
  late _AudioStub audio;

  setUp(() {
    tts = _TtsStub();
    audio = _AudioStub();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ttsEngineProvider.overrideWith((ref) async => tts),
        phonemeAudioProvider.overrideWithValue(audio),
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
    testWidgets('点击字母格 → 弹窗展示字母/音标/例词/拼写/发音按钮', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('A a'));
      await tester.pumpAndSettle();

      expect(find.text('A a'), findsNWidgets(2)); // 格子 + 弹窗符号位
      expect(find.text('/eɪ/'), findsNWidgets(2)); // 格子 + 弹窗注脚
      expect(find.text('Apple'), findsOneWidget);
      expect(find.text('/ˈæpəl/'), findsOneWidget); // 拼写行（例词完整音标）
      expect(find.text('苹果'), findsOneWidget);
      expect(find.text('发音'), findsOneWidget);

      // 发音按钮：字母名 + 例词
      await tester.tap(find.text('发音'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['A. Apple']);
    });

    testWidgets('弹窗排版：例词 40sp 珊瑚主角、符号位 28sp', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('A a'));
      await tester.pumpAndSettle();

      final word = tester.widget<Text>(find.text('Apple'));
      expect(word.style?.fontSize, 40);
      expect(word.style?.color, AppColors.primary);

      final symbol = tester.widget<Text>(find.text('A a').last);
      expect(symbol.style?.fontSize, 28);
      expect(symbol.style?.color, AppColors.ink);
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
    testWidgets('点击音标格 → 分类名 + 例词 + 拼写 + 发音「录音 + 例词」', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('音标'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/iː/').first);
      await tester.pumpAndSettle();

      // 弹窗：分类名（Muted 小字）+ 例词 see（珊瑚 40sp）+ 拼写 /siː/
      // 'see' / '/siː/' 各出现 2 次：网格格子 + 弹窗
      expect(find.text('单元音 (12)'), findsOneWidget); // 分组头（带条目数）
      expect(find.text('单元音'), findsOneWidget); // 弹窗注脚只显示组名
      expect(find.text('see'), findsNWidgets(2));
      expect(find.text('/siː/'), findsNWidgets(2));
      expect(find.text('发音'), findsOneWidget);

      await tester.tap(find.text('发音'));
      await tester.pumpAndSettle();
      expect(audio.played, ['/iː/']); // 音标本身：录音

      // 录音与例词之间停一拍（默认 1s）——测试里把时钟推过去
      await tester.pump(ReferenceController.defaultPhonemeWordGap);
      expect(tts.spoken, ['see']); // 例词：TTS（音标不经过 TTS）
    });

    testWidgets('音标大字点击 → 放录音（不走 TTS）', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('音标'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/iː/').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('/iː/').last); // 弹窗大字
      await tester.pumpAndSettle();
      expect(audio.played, ['/iː/']);
      expect(tts.spoken, isEmpty);
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
