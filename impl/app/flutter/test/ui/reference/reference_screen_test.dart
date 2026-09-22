import 'package:contexta/core/components/app_modal.dart';
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

/// 假录音库：记录播放过哪些音标 / 例词（widget 测试里不碰真实 audioplayers）。
class _AudioStub implements PhonemeAudio {
  final List<String> played = [];
  final List<String> playedWords = [];
  final List<String> playedLetterWords = [];
  int stopCount = 0;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<bool> play(String phone) async {
    played.add(phone);
    return true;
  }

  @override
  Future<bool> playWord(String phone) async {
    playedWords.add(phone);
    return true;
  }

  @override
  Future<bool> playLetterWord(String letter, String phone) async {
    playedLetterWords.add(phone);
    return true;
  }
}

class _TtsStub implements TtsEngine {
  final List<String> spoken = [];
  int stopCount = 0;
  void Function(String?)? _onFinished;

  @override
  bool isAvailable() => true;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
    spoken.add(text);
    _onFinished?.call('ctx-1'); // 立刻上报「读完」，连播才不用等超时
    return 'ctx-1';
  }

  @override
  void stop() => stopCount++;

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) =>
      _onFinished = callback;

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

  group('字母格弹层', () {
    testWidgets('点字母格 → 字母 + 常见读音；字母表的例词与发音按钮不在', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('A a'));
      await tester.pumpAndSettle();

      expect(find.text('常见读音 (5)'), findsOneWidget);
      expect(find.text('A a'), findsNWidgets(2), reason: '格子 + 弹层顶部那个字母');
      expect(find.text('/eɪ/'), findsNWidgets(3),
          reason: '格子上的字母名音标 + 弹层字母名音标 + 弹层第一条读音');
      expect(find.text('day'), findsOneWidget);

      expect(find.text('Apple'), findsNothing, reason: '字母表的例词已从弹层去掉');
      expect(find.text('/ˈæpəl/'), findsNothing);
      expect(find.text('苹果'), findsNothing);
      expect(find.text('发音'), findsNothing, reason: '发音按钮已去掉');
      expect(tts.spoken, isEmpty, reason: '打开弹层本身不出声');
    });

    testWidgets('音标格弹窗排版不变：例词 40sp 珊瑚主角、符号位 28sp', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('音标'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('/iː/').first);
      await tester.pumpAndSettle();

      final word = tester.widget<Text>(find.text('see').last);
      expect(word.style?.fontSize, 40);
      expect(word.style?.color, AppColors.primary);

      final symbol = tester.widget<Text>(find.text('/iː/').last);
      expect(symbol.style?.fontSize, 28);
      expect(symbol.style?.color, AppColors.ink);
    });

    testWidgets('关闭按钮关闭弹层', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('A a'));
      await tester.pumpAndSettle();
      expect(find.text('常见读音 (5)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('常见读音 (5)'), findsNothing);
    });
  });

  group('音标格弹窗', () {
    testWidgets('点击音标格 → 分类名 + 例词 + 拼写 + 发音「音标录音 → 例词录音」',
        (tester) async {
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
      expect(audio.played, ['/iː/']); // 先读音标本身（录音）
      expect(audio.playedWords, isEmpty, reason: '例词要等那一拍之后');

      // 音标录音与例词之间停一拍（默认 1s）——测试里把时钟推过去
      await tester.pump(ReferenceController.defaultPhonemeWordGap);
      expect(audio.playedWords, ['/iː/']); // 再读例词（也是录音）
      expect(tts.spoken, isEmpty, reason: '两段都有录音，不走 TTS');
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
      expect(audio.playedWords, isEmpty);
      expect(tts.spoken, isEmpty);
    });

    testWidgets('音标格例词点击 → 放例词录音（不走 TTS）', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('音标'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/iː/').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('see').last); // 弹窗中的例词大字
      await tester.pumpAndSettle();
      expect(audio.playedWords, ['/iː/']);
      expect(audio.played, isEmpty, reason: '点例词不读音标');
      expect(tts.spoken, isEmpty);
    });
  });

  group('音标连播', () {
    /// 高亮中的格子（珊瑚描边）——`_GridCard` 是私有类，按 decoration 找。
    Finder highlightedCards() => find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final decoration = w.decoration;
          if (decoration is! BoxDecoration) return false;
          final border = decoration.border;
          return border is Border && border.top.color == AppColors.primary;
        });

    Future<void> openPhonicsTab(WidgetTester tester) async {
      await tester.tap(find.text('音标'));
      await tester.pumpAndSettle();
    }

    testWidgets('顶部「连播全部」：开播即高亮第一格，停止后高亮清除', (tester) async {
      await pumpScreen(tester);
      await openPhonicsTab(tester);

      expect(find.text('连播全部 48 个'), findsOneWidget);
      expect(highlightedCards(), findsNothing);

      await tester.tap(find.text('连播全部 48 个'));
      await tester.pumpAndSettle();

      expect(audio.played, ['/iː/'], reason: '从第一格开始读');
      expect(highlightedCards(), findsOneWidget);
      expect(
        find.descendant(of: highlightedCards(), matching: find.text('/iː/')),
        findsOneWidget,
        reason: '高亮的应该是当前正在读的那一格',
      );
      expect(find.text('停止'), findsWidgets, reason: '播放中按钮变「停止」');

      await tester.tap(find.text('停止').first);
      await tester.pumpAndSettle();

      expect(find.text('连播全部 48 个'), findsOneWidget);
      expect(highlightedCards(), findsNothing);

      // 停止后即便时间过去，也不该再冒下一格的声音
      await tester.pump(const Duration(seconds: 5));
      expect(audio.played, ['/iː/']);
      expect(audio.playedWords, isEmpty);
    });

    testWidgets('分组按钮：只连播该组，读完自动复位', (tester) async {
      await pumpScreen(tester);
      await openPhonicsTab(tester);

      // 舌侧音只有 /l/ 一个：读完即止，方便断言
      await tester.ensureVisible(find.byTooltip('连播「舌侧音」'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('连播「舌侧音」'));
      await tester.pumpAndSettle();

      expect(audio.played, ['/l/'], reason: '只读这一组');
      expect(
        find.descendant(of: highlightedCards(), matching: find.text('/l/')),
        findsOneWidget,
      );

      // 一格 = 音标录音 → 1s → 例词录音；推过那一拍后就该收尾
      await tester.pump(ReferenceController.defaultPhonemeWordGap);
      await tester.pumpAndSettle();

      expect(audio.playedWords, ['/l/']);
      expect(highlightedCards(), findsNothing, reason: '读完整组后高亮清除');
      expect(find.byTooltip('连播「舌侧音」'), findsOneWidget);
    });

    testWidgets('播放中打开弹窗 → 连播停止（声音不叠）', (tester) async {
      await pumpScreen(tester);
      await openPhonicsTab(tester);

      await tester.tap(find.text('连播全部 48 个'));
      await tester.pumpAndSettle();
      expect(audio.played, ['/iː/']);

      // 打开弹窗（点正在读的那一格）→ 连播应立刻停
      await tester.tap(find.text('/iː/').first);
      await tester.pumpAndSettle();

      expect(highlightedCards(), findsNothing, reason: '连播已停，高亮清除');
      expect(find.text('连播全部 48 个'), findsOneWidget, reason: '按钮复位');

      await tester.pump(const Duration(seconds: 5));
      expect(audio.played, ['/iː/'], reason: '停止后不该再往下读');
      expect(audio.playedWords, isEmpty, reason: '被打断的那一格也不补读例词');

      await tester.tap(find.text('see').last); // 弹窗里的例词大字
      await tester.pumpAndSettle();
      expect(audio.playedWords, ['/iː/'], reason: '手动点例词照常出声');
    });
  });

  group('字母读音（底部弹层 + 连播）', () {
    /// 高亮中的格子 / 读音行（珊瑚描边）——私有 widget，按 decoration 找。
    Finder highlighted() => find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final decoration = w.decoration;
          if (decoration is! BoxDecoration) return false;
          final border = decoration.border;
          return border is Border && border.top.color == AppColors.primary;
        });

    Future<void> openLetter(WidgetTester tester, String cell) async {
      await tester.ensureVisible(find.text(cell));
      await tester.pumpAndSettle();
      await tester.tap(find.text(cell));
      await tester.pumpAndSettle();
    }

    testWidgets('字母格上标了「N 种读音」', (tester) async {
      await pumpScreen(tester);

      /// 某个字母格里的「N 种读音」（卡片内的 InkWell 认这个格子）。
      Finder soundCountOf(String cell) => find.descendant(
            of: find.ancestor(of: find.text(cell), matching: find.byType(InkWell)),
            matching: find.textContaining('种读音'),
          );

      expect(tester.widget<Text>(soundCountOf('A a')).data, '5 种读音');
      expect(tester.widget<Text>(soundCountOf('O o')).data, '6 种读音');
      expect(tester.widget<Text>(soundCountOf('X x')).data, '3 种读音');
      expect(tester.widget<Text>(soundCountOf('B b')).data, '1 种读音');
    });

    testWidgets('点字母格 → 底部弹层：读音行带音标 / 徽章 / 例词 / 例词音标', (tester) async {
      await pumpScreen(tester);
      await openLetter(tester, 'A a');

      final modal = tester.widget<AppModal>(find.byType(AppModal));
      expect(modal.alignment, AppModalAlignment.bottom, reason: '字母详情是底部弹层');

      expect(find.text('常见读音 (5)'), findsOneWidget);
      expect(find.text('day'), findsOneWidget); // 例词取自音标库（/eɪ/ → day）
      expect(find.text('/deɪ/'), findsOneWidget);
      expect(find.text('弱读'), findsOneWidget, reason: '非「常见音」才挂徽章');
      // /eɪ/ 三处：网格格子 + 弹层字母名注脚 + 弹层第一条读音
      expect(find.text('/eɪ/'), findsNWidgets(3));
    });

    testWidgets('点读音 → 只放读音录音；点例词 → 只放例词录音（都不走 TTS）', (tester) async {
      await pumpScreen(tester);
      await openLetter(tester, 'A a');

      await tester.tap(find.text('/eɪ/').last); // 读音行左边的音标
      await tester.pumpAndSettle();
      expect(audio.played, ['/eɪ/']);
      expect(audio.playedWords, isEmpty, reason: '点读音不读例词');
      expect(tts.spoken, isEmpty);

      await tester.tap(find.text('day')); // 读音行右边的例词
      await tester.pumpAndSettle();
      expect(audio.playedWords, ['/eɪ/']);
      expect(audio.played, ['/eɪ/'], reason: '点例词不再读音标');
      expect(tts.spoken, isEmpty);
    });

    testWidgets('组合音行（X 的 /ks/）：点读音兜底读例词、点例词放预生成录音', (tester) async {
      await pumpScreen(tester);
      await openLetter(tester, 'X x');

      expect(find.text('常见读音 (3)'), findsOneWidget);
      expect(find.text('组合音'), findsNWidgets(2));
      expect(find.text('无单独录音'), findsNWidgets(2));
      // 三条例词都取自站点（音标库那套在 X 上对不上：/z/ 是 zoo）
      expect(find.text('box'), findsOneWidget);
      expect(find.text('/bɒks/'), findsOneWidget);
      expect(find.text('exam'), findsOneWidget);
      expect(find.text('xylophone'), findsOneWidget);
      expect(find.text('/ˈzaɪləfəʊn/'), findsOneWidget);
      expect(find.text('少数词'), findsOneWidget);

      // 点读音（左边）：/ks/ 没有读音录音 → 兜底 TTS 读例词（不读 IPA）
      await tester.tap(find.text('/ks/'));
      await tester.pumpAndSettle();
      expect(audio.played, isEmpty);
      expect(tts.spoken, ['box']);

      // 点例词（右边）：放 TTS 预生成的那条录音
      await tester.tap(find.text('box'));
      await tester.pumpAndSettle();
      expect(audio.playedLetterWords, ['/ks/']);
      expect(tts.spoken, ['box'], reason: '有录音就不再走 TTS');
    });

    testWidgets('弹层「连播这 5 种读音」：字母名 → 逐条读音，停止后复位', (tester) async {
      await pumpScreen(tester);
      await openLetter(tester, 'A a');

      expect(find.byTooltip('连播这 5 种读音'), findsOneWidget);
      await tester.tap(find.byTooltip('连播这 5 种读音'));
      await tester.pumpAndSettle();

      expect(tts.spoken, ['A'], reason: '先读字母名');
      expect(
        find.descendant(of: highlighted(), matching: find.text('A a')),
        findsNWidgets(2),
        reason: '读字母名时高亮：弹层里的字母 + 背后的字母格',
      );

      // 字母名读完 → 停一拍 → 第一条读音（高亮从字母转到那一行）
      await tester.pump(ReferenceController.defaultPhonemeWordGap);
      expect(audio.played, ['/eɪ/']);
      expect(
        find.descendant(of: highlighted(), matching: find.text('A a')),
        findsNothing,
        reason: '读到读音时字母不再高亮',
      );
      expect(
        find.descendant(of: highlighted(), matching: find.text('/eɪ/')),
        findsOneWidget,
      );

      // 再一拍 → 它的例词
      await tester.pump(ReferenceController.defaultPhonemeWordGap);
      expect(audio.playedWords, ['/eɪ/']);

      final playedAtStop = [...audio.played];
      await tester.tap(find.byTooltip('停止'));
      await tester.pumpAndSettle();

      expect(highlighted(), findsNothing, reason: '停止后高亮清除');
      expect(find.byTooltip('连播这 5 种读音'), findsOneWidget, reason: '按钮复位');

      await tester.pump(const Duration(seconds: 5));
      expect(audio.played, playedAtStop, reason: '停止后不再往下读');
    });

    testWidgets('弹层里关闭弹窗 → 该字母的连播停止', (tester) async {
      await pumpScreen(tester);
      await openLetter(tester, 'A a');

      await tester.tap(find.byTooltip('连播这 5 种读音'));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['A']);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 5));
      expect(audio.played, isEmpty, reason: '关闭弹层后不再出声');
      expect(tts.stopCount, greaterThan(0), reason: '字母名也要掐掉');
    });

    testWidgets('顶部「连播全部 26 个字母」：开播高亮 A 格，停止后清除', (tester) async {
      await pumpScreen(tester);

      expect(find.text('连播全部 26 个字母'), findsOneWidget);
      await tester.tap(find.text('连播全部 26 个字母'));
      await tester.pumpAndSettle();

      expect(tts.spoken, ['A']);
      expect(
        find.descendant(of: highlighted(), matching: find.text('A a')),
        findsOneWidget,
        reason: '高亮当前字母格',
      );
      expect(find.text('停止'), findsOneWidget, reason: '播放中按钮变「停止」');

      await tester.pump(ReferenceController.defaultPhonemeWordGap);
      expect(audio.played, ['/eɪ/']);

      await tester.tap(find.text('停止'));
      await tester.pumpAndSettle();

      expect(find.text('连播全部 26 个字母'), findsOneWidget);
      expect(highlighted(), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      expect(audio.played, ['/eɪ/'], reason: '停止后不再冒下一格的声音');
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
