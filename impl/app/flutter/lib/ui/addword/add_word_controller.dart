import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/model/word_detail.dart';
import '../../domain/usecase/add_word_usecase.dart';

/// AddWord 页 UI 状态（对照 Kotlin AddWordUiState）。
class AddWordUiState {
  const AddWordUiState({
    this.input = '',
    this.isSubmitting = false,
    this.stageMessage,
    this.success,
    this.error,
    this.invalidInput,
  });

  final String input;
  final bool isSubmitting;

  /// 提交中的进度文案（对照 Kotlin stageMessage）。
  final String? stageMessage;

  /// 录入成功数据（非 null 时展示结果页）。
  final AddWordSuccessData? success;
  final String? error;
  final String? invalidInput;

  AddWordUiState copyWith({
    String? input,
    bool? isSubmitting,
    Object? stageMessage = _unset,
    Object? success = _unset,
    Object? error = _unset,
    Object? invalidInput = _unset,
  }) =>
      AddWordUiState(
        input: input ?? this.input,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        stageMessage: identical(stageMessage, _unset)
            ? this.stageMessage
            : stageMessage as String?,
        success: identical(success, _unset)
            ? this.success
            : success as AddWordSuccessData?,
        error: identical(error, _unset) ? this.error : error as String?,
        invalidInput: identical(invalidInput, _unset)
            ? this.invalidInput
            : invalidInput as String?,
      );

  static const Object _unset = Object();
}

/// 录入成功数据（对照 Kotlin AddWordSuccessData）。
class AddWordSuccessData {
  const AddWordSuccessData({
    required this.word,
    this.phonetic,
    this.senses = const [],
    required this.alreadyExisted,
    required this.addedToVocabulary,
  });

  final String word;
  final String? phonetic;
  final List<WordSense> senses;
  final bool alreadyExisted;
  final bool addedToVocabulary;
}

/// AddWord 页控制器（对照 Kotlin AddWordViewModel）：
/// - 输入变化时清空错误/结果
/// - submit：调用 AddWordUseCase（阶段回调更新进度文案），按结果分类
///   Success / AlreadyExists → 结果页；InvalidInput / Failed → 错误展示
/// - reset：清空状态录入下一个单词
class AddWordController extends StateNotifier<AddWordUiState> {
  AddWordController({
    required this._addWordUseCase,
  }) : super(const AddWordUiState());

  final AddWordUseCase _addWordUseCase;

  void onInputChange(String value) {
    state = state.copyWith(
      input: value,
      invalidInput: null,
      error: null,
      success: null,
    );
  }

  Future<void> submit() async {
    final input = state.input;
    if (input.trim().isEmpty || state.isSubmitting) return;

    state = state.copyWith(
      isSubmitting: true,
      invalidInput: null,
      error: null,
      success: null,
      stageMessage: '正在检查本地词库…',
    );

    final result = await _addWordUseCase.call(
      input,
      onStage: (stage) {
        state = state.copyWith(
          stageMessage: switch (stage) {
            AddWordStage.checkingLocal => '正在检查本地词库…',
            AddWordStage.generating => '正在通过 AI 生成音标、释义与例句…',
          },
        );
      },
    );

    switch (result) {
      case AddWordResultSuccess(:final detail, :final addedToVocabulary):
        state = state.copyWith(
          isSubmitting: false,
          stageMessage: null,
          success: AddWordSuccessData(
            word: detail.spellingDisplay,
            phonetic: detail.phoneticIpa,
            senses: detail.allSenses,
            alreadyExisted: false,
            addedToVocabulary: addedToVocabulary,
          ),
        );
      case AddWordResultAlreadyExists(
          :final detail,
          :final addedToVocabulary
        ):
        state = state.copyWith(
          isSubmitting: false,
          stageMessage: null,
          success: AddWordSuccessData(
            word: detail.spellingDisplay,
            phonetic: detail.phoneticIpa,
            senses: detail.allSenses,
            alreadyExisted: true,
            addedToVocabulary: addedToVocabulary,
          ),
        );
      case AddWordResultInvalidInput(:final message):
        state = state.copyWith(
          isSubmitting: false,
          stageMessage: null,
          invalidInput: message,
        );
      case AddWordResultFailed(:final message):
        state = state.copyWith(
          isSubmitting: false,
          stageMessage: null,
          error: message,
        );
    }
  }

  /// 清空状态，录入下一个单词。
  void reset() {
    state = const AddWordUiState();
  }
}

/// AddWord 页控制器 Provider。
final addWordControllerProvider =
    StateNotifierProvider.autoDispose<AddWordController, AddWordUiState>(
        (ref) {
  return AddWordController(
    addWordUseCase: ref.watch(addWordUseCaseProvider),
  );
});
