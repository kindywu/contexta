import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/components/app_button.dart';
import '../../core/components/app_card.dart';
import '../../core/components/app_top_bar.dart';
import '../../core/components/loading_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import '../../domain/model/word_detail.dart';
import 'add_word_controller.dart';

/// AddWord 页（对照 Kotlin AddWordScreen.kt）：
/// - 顶栏「录入单词」+ 返回
/// - 输入态：AppCard 内「输入英文单词」标题 + OutlinedTextField +
///   「生成释义并加入生词库」按钮（空白/提交中禁用）+ 说明文案；
///   invalidInput 红字 / error 卡片（重试按钮）；提交中 LoadingIndicator
///   （阶段进度文案）
/// - 结果态：加入状态徽标（✓ 已加入生词库 / • 该词已在生词库中）+
///   单词详情卡（词头 22sp + 音标 + SenseBlock 词性块）+
///   「再录一个」+「返回生词本」
class AddWordScreen extends ConsumerStatefulWidget {
  const AddWordScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends ConsumerState<AddWordScreen> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addWordControllerProvider);
    final controller = ref.read(addWordControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          AppTopBar(title: '录入单词', onBack: widget.onBack),
          Expanded(
            child: state.success != null
                ? _AddWordResultContent(
                    success: state.success!,
                    onAddAnother: controller.reset,
                    onDone: widget.onBack,
                  )
                : _AddWordInputContent(
                    state: state,
                    controller: controller,
                    inputController: _inputController,
                  ),
          ),
        ],
      ),
    );
  }
}

/// 输入态内容（对照 Kotlin AddWordInputContent）。
class _AddWordInputContent extends StatelessWidget {
  const _AddWordInputContent({
    required this.state,
    required this.controller,
    required this.inputController,
  });

  final AddWordUiState state;
  final AddWordController controller;
  final TextEditingController inputController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '输入英文单词',
                style: AppType.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: inputController,
                onChanged: controller.onInputChange,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => controller.submit(),
                inputFormatters: [
                  // 对照 Kotlin WORD_PATTERN 的前置过滤：输入时即拦截非法字符
                  FilteringTextInputFormatter.allow(
                    RegExp(r"[A-Za-z'\- ]"),
                  ),
                ],
                decoration: InputDecoration(
                  hintText: '例如：serendipity',
                  hintStyle: AppType.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.mutedSoft),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: AppColors.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                ),
                style: AppType.textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                text: '生成释义并加入生词库',
                onClick: controller.submit,
                enabled: state.input.trim().isNotEmpty && !state.isSubmitting,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '本地词库没有该词时，将调用 AI 生成音标、释义与例句',
                style: AppType.textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (state.invalidInput != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            state.invalidInput!,
            style: AppType.textTheme.bodyMedium
                ?.copyWith(color: AppColors.error),
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  state.error!,
                  style: AppType.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.bodyText),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(text: '重试', onClick: controller.submit),
                ),
              ],
            ),
          ),
        ],
        if (state.isSubmitting) ...[
          const SizedBox(height: AppSpacing.lg),
          LoadingIndicator(
            message: state.stageMessage ?? '处理中…',
          ),
        ],
      ],
    );
  }
}

/// 结果态内容（对照 Kotlin AddWordResultContent）：
/// 状态徽标 + 单词详情卡 + 再录一个 / 返回生词本。
class _AddWordResultContent extends StatelessWidget {
  const _AddWordResultContent({
    required this.success,
    required this.onAddAnother,
    required this.onDone,
  });

  final AddWordSuccessData success;
  final VoidCallback onAddAnother;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // 加入状态徽标
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (success.addedToVocabulary)
                Icon(Icons.check_circle_outline,
                    size: 20, color: AppColors.success)
              else
                Text(
                  '•',
                  style: AppType.textTheme.titleMedium
                      ?.copyWith(color: AppColors.muted),
                ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  switch ((success.addedToVocabulary, success.alreadyExisted)) {
                    (true, true) => '已加入生词库（复用本地词库释义）',
                    (true, false) => '已加入生词库',
                    (false, _) => '该词已在生词库中',
                  },
                  style: AppType.textTheme.bodyMedium?.copyWith(
                    color: success.addedToVocabulary
                        ? AppColors.success
                        : AppColors.bodyText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // 单词详情卡
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                success.word,
                textAlign: TextAlign.center,
                style: AppType.textTheme.headlineLarge
                    ?.copyWith(color: AppColors.ink),
              ),
              if (success.phonetic != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  success.phonetic!,
                  textAlign: TextAlign.center,
                  style: AppType.phonetic,
                ),
              ],
              for (final sense in success.senses) ...[
                const SizedBox(height: AppSpacing.md),
                _SenseBlock(sense: sense),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(text: '再录一个', onClick: onAddAnother),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          text: '返回生词本',
          onClick: onDone,
          variant: AppButtonVariant.secondary,
        ),
      ],
    );
  }
}

/// 词性块（对照 Kotlin AddWordScreen.SenseBlock：SurfaceSoft + 10dp 圆角）。
class _SenseBlock extends StatelessWidget {
  const _SenseBlock({required this.sense});

  final WordSense sense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  sense.partOfSpeech,
                  style: AppType.textTheme.labelLarge
                      ?.copyWith(color: AppColors.primary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sense.chineseMeaning,
                      style: AppType.textTheme.titleSmall
                          ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sense.englishDefinition,
                      style: AppType.textTheme.bodySmall
                          ?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final example in sense.examples) ...[
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  example.sentenceEn,
                  style: AppType.textTheme.bodySmall
                      ?.copyWith(color: AppColors.bodyText),
                ),
                Text(
                  example.sentenceZh,
                  style: AppType.textTheme.bodySmall
                      ?.copyWith(color: AppColors.mutedSoft),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
