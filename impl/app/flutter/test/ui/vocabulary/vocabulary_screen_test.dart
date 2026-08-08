import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/model/word_detail.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/vocabulary/vocabulary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vocabulary 页 widget 测试（Task 25）。
/// 逻辑已由 vocabulary_controller_test 覆盖（11 个），此处验证 UI 接线：
/// - 顶栏（返回 / 进度点 / 录入）、复习卡渲染、✓ FAB 标记认识
/// - 空态 EmptyState；全部复习完 → 总结页 + 再来一轮
/// - 路由接线（app_router_test 覆盖）：onAddWord / onBack 回调

class _FakeSettingsRepo implements SettingsRepository {
  @override
  Future<UserSettings?> getSettings() async =>
      const UserSettings(isOnboarded: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeVocabRepo implements VocabularyRepository {
  /// 活跃列表（可变：测试可直接赋值模拟 DB 状态）。
  List<VocabWord> words = [];

  @override
  Future<List<VocabWord>> getActiveWords() async => words;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _TtsStub implements TtsEngine {
  final List<String> spoken = [];

  @override
  bool isAvailable() => true;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0}) {
    spoken.add(text);
    return 'ctx-1';
  }

  @override
  void stop() {}

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {}
}

VocabWord vocabWord({
  int entryId = 1,
  String spelling = 'hello',
  String? phonetic,
  int streak = 0,
  List<WordSense> senses = const [],
}) =>
    VocabWord(
      entryId: entryId,
      wordId: 1,
      instanceNumber: 1,
      status: VocabStatus.new_,
      correctReviewStreak: streak,
      spellingDisplay: spelling,
      phoneticIpa: phonetic,
      allSenses: senses,
    );

WordSense sense({
  String partOfSpeech = 'interj.',
  String chineseMeaning = '你好',
  String englishDefinition = 'Used as a greeting.',
}) =>
    WordSense(
      id: 1,
      orderIndex: 1,
      partOfSpeech: partOfSpeech,
      chineseMeaning: chineseMeaning,
      englishDefinition: englishDefinition,
      examples: [
        ExampleSentence(
          id: 1,
          orderIndex: 1,
          sentenceEn: 'Hello world.',
          sentenceZh: '你好世界。',
          isPrimary: true,
        ),
      ],
    );

/// 内容超长的词（词头必然被滚出屏幕）。
VocabWord longWord(int entryId, String spelling) => vocabWord(
      entryId: entryId,
      spelling: spelling,
      senses: [
        for (var i = 0; i < 30; i++)
          sense(
            partOfSpeech: 'n.$i',
            chineseMeaning: '义项 $i',
            englishDefinition:
                'A very long definition number $i that keeps going '
                'and going and going and going and going.',
          ),
      ],
    );

void main() {
  late _FakeSettingsRepo settingsRepo;
  late _FakeVocabRepo vocabRepo;
  var onBackCalled = false;
  var onAddWordCalled = false;

  setUp(() {
    settingsRepo = _FakeSettingsRepo();
    vocabRepo = _FakeVocabRepo();
    onBackCalled = false;
    onAddWordCalled = false;
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        vocabularyRepositoryProvider.overrideWithValue(vocabRepo),
        ttsEngineProvider.overrideWith((ref) async => _TtsStub()),
      ],
      child: MaterialApp(
        home: VocabularyScreen(
          onBack: () => onBackCalled = true,
          onAddWord: () => onAddWordCalled = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('顶栏', () {
    testWidgets('返回 / 录入按钮触发回调', (tester) async {
      vocabRepo.words = [vocabWord()];
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(onBackCalled, isTrue);

      await tester.tap(find.byIcon(Icons.add));
      expect(onAddWordCalled, isTrue);
    });

    testWidgets('进度显示 当前/总数 + 分段点', (tester) async {
      vocabRepo.words = [
        vocabWord(entryId: 1, spelling: 'alpha'),
        vocabWord(entryId: 2, spelling: 'beta'),
        vocabWord(entryId: 3, spelling: 'gamma'),
      ];
      await pumpScreen(tester);

      expect(find.text('1 / 3'), findsOneWidget);
      // 3 个分段点：当前段 16dp 宽，其余 6dp
      final dots = tester
          .widgetList<Container>(find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxWidth == 16))
          .length;
      expect(dots, 1);
    });
  });

  group('复习卡', () {
    testWidgets('渲染词头/音标/词性块/例句/认识次数', (tester) async {
      vocabRepo.words = [
        vocabWord(
          spelling: 'hello',
          phonetic: '/həˈləʊ/',
          senses: [sense()],
        ),
      ];
      await pumpScreen(tester);

      expect(find.text('hello'), findsOneWidget);
      expect(find.text('/həˈləʊ/'), findsOneWidget);
      expect(find.text('interj.'), findsOneWidget);
      expect(find.text('你好'), findsOneWidget);
      expect(find.text('Used as a greeting.'), findsOneWidget);
      expect(find.text('Hello world.'), findsOneWidget);
      expect(find.text('你好世界。'), findsOneWidget);
      expect(find.text('已认识 0/1 次'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('点击发音钮 → TTS speak', (tester) async {
      final tts = _TtsStub();
      vocabRepo.words = [vocabWord(spelling: 'hello')];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          vocabularyRepositoryProvider.overrideWithValue(vocabRepo),
          ttsEngineProvider.overrideWith((ref) async => tts),
        ],
        child: MaterialApp(
          home: VocabularyScreen(onBack: () {}, onAddWord: () {}),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.volume_up_outlined));
      await tester.pump();
      expect(tts.spoken, ['hello']);
    });
  });

  group('复习流程 UI', () {
    testWidgets('✓ FAB 标记认识 → 进度推进到 2 / 2', (tester) async {
      vocabRepo.words = [
        vocabWord(entryId: 1, spelling: 'alpha'),
        vocabWord(entryId: 2, spelling: 'beta'),
      ];
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
    });

    testWidgets('全部复习完 → 总结页（统计 + 再来一轮）', (tester) async {
      vocabRepo.words = [vocabWord(entryId: 1, spelling: 'alpha')];
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(find.text('复习完成！'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // 复习单词
      expect(find.text('新标记认识'), findsOneWidget);
      expect(find.text('再来一轮'), findsOneWidget);

      // 再来一轮 → 回到复习卡
      await tester.tap(find.text('再来一轮'));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('复习完成！'), findsNothing);
    });
  });

  group('切词滚动位置', () {
    testWidgets('长词滚到底后切下一个词 → 新词内容回到顶部', (tester) async {
      // 两个词内容都超长；若不重置滚动位置，词2 会延续词1 的滚动 offset，
      // 词头被顶出屏幕
      vocabRepo.words = [
        longWord(1, 'antidisestablishmentarianism'),
        longWord(2, 'beta'),
      ];
      await pumpScreen(tester);

      // 词1 滚到底（offset > 0 即为滚出状态）
      final scrollable = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView));
      scrollable.controller!.jumpTo(scrollable.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(scrollable.controller!.offset, greaterThan(0));

      // 点 ✓ 切到词2
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // 词2 滚动位置重置在顶部（词头可见）——修复的核心行为契约
      final after = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView));
      expect(after.controller!.offset, 0);
    });
  });

  group('空态', () {
    testWidgets('生词表为空 → EmptyState 文案', (tester) async {
      await pumpScreen(tester);

      expect(find.text('生词表为空'), findsOneWidget);
      expect(find.text('阅读时点击单词可加入生词表'), findsOneWidget);
    });
  });
}
