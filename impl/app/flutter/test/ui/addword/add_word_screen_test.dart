import 'package:contexta/core/components/app_button.dart';
import 'package:contexta/core/components/loading_indicator.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/llm_client.dart';
import 'package:contexta/domain/model/word_detail.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/repository/word_repository.dart';
import 'package:contexta/domain/usecase/add_word_usecase.dart';
import 'package:contexta/ui/addword/add_word_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// AddWord 页 widget 测试（Task 27）。
/// 逻辑已由 add_word_controller_test 覆盖（8 个），此处验证 UI 接线：
/// - 初始输入态：标题/输入框/按钮禁用态/说明文案
/// - 输入变化启用按钮；提交中显示 LoadingIndicator + 阶段文案
/// - 结果态：徽标文案（加入/复用/已存在）+ 单词详情 + 再录一个/返回生词本
/// - invalidInput / error 展示
/// - 路由接线（app_router_test 覆盖）

class _FakeAddWordUseCase extends AddWordUseCase {
  _FakeAddWordUseCase({required this.result})
      : super(
          wordRepository: _NeverWordRepo(),
          vocabularyRepository: _NeverVocabRepo(),
          statsRepository: _NeverStatsRepo(),
          llmClient: _NeverLlmClient(),
        );

  final AddWordResult result;
  String? lastInput;

  @override
  Future<AddWordResult> call(
    String rawInput, {
    void Function(AddWordStage stage)? onStage,
  }) async {
    lastInput = rawInput;
    onStage?.call(AddWordStage.checkingLocal);
    await Future<void>.delayed(Duration.zero);
    onStage?.call(AddWordStage.generating);
    return result;
  }
}

class _NeverWordRepo implements WordRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _NeverVocabRepo implements VocabularyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _NeverStatsRepo implements StatsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _NeverLlmClient implements LlmClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

const _detail = WordDetail(
  wordId: 10,
  spellingDisplay: 'serendipity',
  phoneticIpa: '/ˌserənˈdɪpəti/',
  primarySense: null,
  allSenses: [
    WordSense(
      id: 1,
      orderIndex: 1,
      partOfSpeech: 'n.',
      chineseMeaning: '意外发现珍奇事物的运气',
      englishDefinition: 'The occurrence of events by chance in a happy way.',
      examples: [
        ExampleSentence(
          id: 1,
          orderIndex: 1,
          sentenceEn: 'Finding this book was pure serendipity.',
          sentenceZh: '找到这本书纯属意外之喜。',
          isPrimary: true,
        ),
      ],
    ),
  ],
);

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    AddWordResult result,
  ) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        addWordUseCaseProvider.overrideWithValue(
          _FakeAddWordUseCase(result: result),
        ),
      ],
      child: const MaterialApp(home: AddWordScreen(onBack: _noop)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> enterWord(WidgetTester tester, String word) async {
    await tester.enterText(find.byType(TextField), word);
    await tester.pumpAndSettle();
  }

  group('输入态', () {
    testWidgets('初始渲染：标题/输入框/禁用按钮/说明文案', (tester) async {
      await pumpScreen(
        tester,
        const AddWordResultInvalidInput(message: 'x'),
      );

      expect(find.text('录入单词'), findsOneWidget);
      expect(find.text('输入英文单词'), findsOneWidget);
      expect(find.text('例如：serendipity'), findsOneWidget);
      expect(find.text('生成释义并加入生词库'), findsOneWidget);
      expect(find.text('本地词库没有该词时，将调用 AI 生成音标、释义与例句'),
          findsOneWidget);

      // 初始按钮禁用（空白输入）：AppButton 禁用态 → InkWell onTap 为 null
      final inkWell = tester.widget<InkWell>(find.descendant(
        of: find.byType(AppButton),
        matching: find.byType(InkWell),
      ));
      expect(inkWell.onTap, isNull);
    });

    testWidgets('输入后按钮启用；提交中显示 LoadingIndicator + 阶段文案',
        (tester) async {
      await pumpScreen(
        tester,
        AddWordResultSuccess(detail: _detail, addedToVocabulary: true),
      );

      await enterWord(tester, 'serendipity');

      final inkWell = tester.widget<InkWell>(find.descendant(
        of: find.byType(AppButton),
        matching: find.byType(InkWell),
      ));
      expect(inkWell.onTap, isNotNull);

      await tester.tap(find.text('生成释义并加入生词库'));
      await tester.pump(); // 进入提交中
      expect(find.byType(LoadingIndicator), findsOneWidget);
      expect(find.text('正在检查本地词库…'), findsOneWidget);

      await tester.pumpAndSettle(); // 提交完成 → 结果态
      expect(find.byType(LoadingIndicator), findsNothing);
      expect(find.text('已加入生词库'), findsOneWidget);
    });
  });

  group('结果态', () {
    testWidgets('成功：徽标 + 单词详情 + 再录一个 / 返回生词本', (tester) async {
      await pumpScreen(
        tester,
        AddWordResultSuccess(detail: _detail, addedToVocabulary: true),
      );
      await enterWord(tester, 'serendipity');
      await tester.tap(find.text('生成释义并加入生词库'));
      await tester.pumpAndSettle();

      expect(find.text('已加入生词库'), findsOneWidget);
      expect(find.text('serendipity'), findsOneWidget);
      expect(find.text('/ˌserənˈdɪpəti/'), findsOneWidget);
      expect(find.text('n.'), findsOneWidget);
      expect(find.text('意外发现珍奇事物的运气'), findsOneWidget);
      expect(find.text('Finding this book was pure serendipity.'), findsOneWidget);
      expect(find.text('找到这本书纯属意外之喜。'), findsOneWidget);
      expect(find.text('再录一个'), findsOneWidget);
      expect(find.text('返回生词本'), findsOneWidget);
    });

    testWidgets('复用本地词库释义徽标', (tester) async {
      await pumpScreen(
        tester,
        AddWordResultSuccess(detail: _detail, addedToVocabulary: true),
      );
      await enterWord(tester, 'serendipity');
      await tester.tap(find.text('生成释义并加入生词库'));
      await tester.pumpAndSettle();

      // 已加入生词库（非复用本地）→ 只显示 '已加入生词库'
      expect(find.text('已加入生词库（复用本地词库释义）'), findsNothing);
    });

    testWidgets('已在生词库中徽标（复用本地词库释义）', (tester) async {
      await pumpScreen(
        tester,
        const AddWordResultAlreadyExists(
          detail: _detail,
          addedToVocabulary: false,
        ),
      );
      await enterWord(tester, 'serendipity');
      await tester.tap(find.text('生成释义并加入生词库'));
      await tester.pumpAndSettle();

      expect(find.text('该词已在生词库中'), findsOneWidget);
    });

    testWidgets('再录一个 → 回到输入态', (tester) async {
      await pumpScreen(
        tester,
        AddWordResultSuccess(detail: _detail, addedToVocabulary: true),
      );
      await enterWord(tester, 'serendipity');
      await tester.tap(find.text('生成释义并加入生词库'));
      await tester.pumpAndSettle();
      expect(find.text('已加入生词库'), findsOneWidget);

      await tester.tap(find.text('再录一个'));
      await tester.pumpAndSettle();

      expect(find.text('输入英文单词'), findsOneWidget);
      expect(find.text('已加入生词库'), findsNothing);
    });

    testWidgets('返回生词本 → onBack 回调', (tester) async {
      var backCalled = false;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          addWordUseCaseProvider.overrideWithValue(
            _FakeAddWordUseCase(
              result: AddWordResultSuccess(
                  detail: _detail, addedToVocabulary: true),
            ),
          ),
        ],
        child: MaterialApp(
          home: AddWordScreen(onBack: () => backCalled = true),
        ),
      ));
      await tester.pumpAndSettle();
      await enterWord(tester, 'serendipity');
      await tester.tap(find.text('生成释义并加入生词库'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('返回生词本'));
      await tester.pumpAndSettle();
      expect(backCalled, isTrue);
    });
  });

  group('错误展示', () {
    testWidgets('invalidInput → 红色错误文案', (tester) async {
      await pumpScreen(
        tester,
        const AddWordResultInvalidInput(message: '只能输入英文字母'),
      );
      await enterWord(tester, '你好123');
      // 中文被输入过滤器拦截 → 输入保持为空 → 按钮禁用 → 不会提交
      expect(find.text('只能输入英文字母'), findsNothing);

      // 输入合法英文后提交 → invalidInput 展示
      await enterWord(tester, '123abc');
      await tester.tap(find.text('生成释义并加入生词库'));
      await tester.pumpAndSettle();

      expect(find.text('只能输入英文字母'), findsOneWidget);
      expect(find.text('输入英文单词'), findsOneWidget); // 仍在输入态
    });

    testWidgets('Failed → 错误卡片 + 重试按钮', (tester) async {
      await pumpScreen(
        tester,
        const AddWordResultFailed(message: '网络不稳定'),
      );
      await enterWord(tester, 'serendipity');

      await tester.tap(find.text('生成释义并加入生词库'));
      await tester.pumpAndSettle();

      expect(find.text('网络不稳定'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });
}

void _noop() {}
