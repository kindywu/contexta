import 'package:contexta/data/remote/llm_api.dart';
import 'package:contexta/domain/model/word_detail.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/repository/word_repository.dart';
import 'package:contexta/domain/usecase/add_word_usecase.dart';
import 'package:contexta/ui/addword/add_word_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// AddWord 页 controller 测试（Task 27）。
/// 对照 Kotlin AddWordViewModel 行为契约：
/// - 输入变化清空错误/结果
/// - submit：Success / AlreadyExists → 结果数据；InvalidInput / Failed → 错误
/// - 阶段回调更新进度文案；空白输入 / 提交中忽略
/// - reset 清空状态

class _FakeAddWordUseCase extends AddWordUseCase {
  _FakeAddWordUseCase({required this.result})
      : super(
          wordRepository: _NeverWordRepo(),
          vocabularyRepository: _NeverVocabRepo(),
          statsRepository: _NeverStatsRepo(),
          llmApi: _NeverLlmApi(),
        );

  final AddWordResult result;
  final List<AddWordStage> stages = [];
  String? lastInput;

  @override
  Future<AddWordResult> call(
    String rawInput, {
    void Function(AddWordStage stage)? onStage,
  }) async {
    lastInput = rawInput;
    // 异步间隙模拟真实调用链：每个阶段 emit 之间有 await 边界，
    // 测试才能观察到中间进度文案
    onStage?.call(AddWordStage.checkingLocal);
    stages.add(AddWordStage.checkingLocal);
    await Future<void>.delayed(Duration.zero);
    onStage?.call(AddWordStage.generating);
    stages.add(AddWordStage.generating);
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

class _NeverLlmApi implements LlmApi {
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
  group('输入变化', () {
    test('onInputChange 更新输入并清空错误/结果', () async {
      final controller = AddWordController(
        addWordUseCase: _FakeAddWordUseCase(
            result: AddWordResultFailed(message: 'x')),
      );
      controller.onInputChange('hello');
      expect(controller.state.input, 'hello');
      expect(controller.state.invalidInput, isNull);

      await controller.submit();
      expect(controller.state.error, 'x');

      controller.onInputChange('hi');
      expect(controller.state.input, 'hi');
      expect(controller.state.error, isNull);
      expect(controller.state.success, isNull);
      controller.dispose();
    });
  });

  group('submit', () {
    test('Success → 结果数据（addedToVocabulary + 阶段进度）', () async {
      final useCase = _FakeAddWordUseCase(
        result: AddWordResultSuccess(detail: _detail, addedToVocabulary: true),
      );
      final controller = AddWordController(addWordUseCase: useCase);
      controller.onInputChange('serendipity');

      final submitFuture = controller.submit();
      expect(controller.state.isSubmitting, isTrue);
      expect(controller.state.stageMessage, '正在检查本地词库…');

      await submitFuture;

      expect(useCase.lastInput, 'serendipity');
      expect(
        useCase.stages,
        [AddWordStage.checkingLocal, AddWordStage.generating],
      );
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.stageMessage, isNull);
      final success = controller.state.success!;
      expect(success.word, 'serendipity');
      expect(success.phonetic, '/ˌserənˈdɪpəti/');
      expect(success.senses.single.partOfSpeech, 'n.');
      expect(success.alreadyExisted, isFalse);
      expect(success.addedToVocabulary, isTrue);
      expect(controller.state.error, isNull);
    });

    test('AlreadyExists → 结果数据（alreadyExisted=true）', () async {
      final controller = AddWordController(
        addWordUseCase: _FakeAddWordUseCase(
          result: AddWordResultAlreadyExists(
              detail: _detail, addedToVocabulary: false),
        ),
      );
      controller.onInputChange('serendipity');

      await controller.submit();

      expect(controller.state.success!.alreadyExisted, isTrue);
      expect(controller.state.success!.addedToVocabulary, isFalse);
    });

    test('InvalidInput → invalidInput 错误文案', () async {
      final controller = AddWordController(
        addWordUseCase: _FakeAddWordUseCase(
          result: const AddWordResultInvalidInput(message: '只能输入英文字母'),
        ),
      );
      controller.onInputChange('你好123');

      await controller.submit();

      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.invalidInput, '只能输入英文字母');
      expect(controller.state.success, isNull);
    });

    test('Failed → error 错误文案', () async {
      final controller = AddWordController(
        addWordUseCase: _FakeAddWordUseCase(
          result: const AddWordResultFailed(message: '网络不稳定'),
        ),
      );
      controller.onInputChange('hello');

      await controller.submit();

      expect(controller.state.error, '网络不稳定');
      expect(controller.state.success, isNull);
    });

    test('空白输入 → 不提交', () async {
      final useCase = _FakeAddWordUseCase(
        result: AddWordResultSuccess(detail: _detail, addedToVocabulary: true),
      );
      final controller = AddWordController(addWordUseCase: useCase);

      controller.onInputChange('   ');
      await controller.submit();

      expect(useCase.lastInput, isNull);
      expect(controller.state.isSubmitting, isFalse);
    });

    test('提交中重复 submit → 忽略', () async {
      final useCase = _FakeAddWordUseCase(
        result: AddWordResultSuccess(detail: _detail, addedToVocabulary: true),
      );
      final controller = AddWordController(addWordUseCase: useCase);
      controller.onInputChange('hello');

      // useCase.call 挂起期间重复提交应被忽略
      final first = controller.submit();
      await controller.submit(); // 同步路径：isSubmitting=true 时直接 return
      await first;

      expect(controller.state.isSubmitting, isFalse);
    });
  });

  group('reset', () {
    test('reset 清空状态（录入下一个单词）', () async {
      final controller = AddWordController(
        addWordUseCase: _FakeAddWordUseCase(
          result: AddWordResultSuccess(detail: _detail, addedToVocabulary: true),
        ),
      );
      controller.onInputChange('serendipity');
      await controller.submit();
      expect(controller.state.success, isNotNull);

      controller.reset();

      expect(controller.state.input, '');
      expect(controller.state.success, isNull);
      expect(controller.state.error, isNull);
      expect(controller.state.isSubmitting, isFalse);
    });
  });
}
