import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/components/app_button.dart';
import '../core/components/loading_indicator.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_type.dart';
import '../ui/vocabulary/vocabulary_controller.dart';
import 'pad_layout.dart';
import '../ui/vocabulary/vocabulary_screen.dart' show VocabularyCard;

/// Pad 生词本：**闪卡居中 + 右侧统计栏**。
///
/// 平板横向空间充裕，手机上的「一次一张卡、满屏宽度」在大屏上读起来很累——
/// 这里把卡片限宽居中，右侧常驻本次复习的进度与统计（手机版把这些放在卡内
/// 与顶栏，大屏可以摊开）。
///
/// 复习流程（认识 / 不认识 / 上一个 / 重来）与手机完全一致，只是布局不同；
/// 数据复用同一个 `vocabularyControllerProvider`。
class PadVocabularyScreen extends ConsumerStatefulWidget {
  const PadVocabularyScreen({
    super.key,
    required this.onBack,
    required this.onAddWord,
  });

  final VoidCallback onBack;
  final VoidCallback onAddWord;

  @override
  ConsumerState<PadVocabularyScreen> createState() =>
      _PadVocabularyScreenState();
}

class _PadVocabularyScreenState extends ConsumerState<PadVocabularyScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(vocabularyControllerProvider.notifier).loadVocabulary();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vocabularyControllerProvider);
    final controller = ref.read(vocabularyControllerProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 右侧统计栏只在真的放得下时才出现（< 900dp 时让位给卡片）
        final showStats = constraints.maxWidth >= 900;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildMain(state, controller)),
            if (showStats) ...[
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppColors.hairline,
              ),
              SizedBox(
                width: 280,
                child: _PadReviewStats(state: state),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMain(VocabularyUiState state, VocabularyController controller) {
    if (state.isLoading) return const LoadingIndicator();

    if (state.totalCount == 0) {
      return const Center(
        child: EmptyState(
          icon: Icons.edit_note_outlined,
          message: '生词表为空',
          subMessage: '阅读时点击单词可加入生词表',
        ),
      );
    }

    if (state.isSummary) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('本轮复习完成', style: AppType.textTheme.headlineLarge),
            const SizedBox(height: AppSpacing.md),
            Text(
              '认识 ${state.newlyKnownCount} / 共 ${state.reviewedCount} 个',
              style: AppType.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.mutedSoft),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(text: '再来一轮', onClick: controller.restart),
          ],
        ),
      );
    }

    final word = state.currentWord;
    if (word == null) return const SizedBox.shrink();

    return Column(
      children: [
        _PadVocabularyTopBar(
          currentIndex: state.currentIndex,
          totalCount: state.totalCount,
          onBack: widget.onBack,
          onAddWord: widget.onAddWord,
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              // 卡片限宽：大屏下不让单行文字拉太长（典型平板阅读宽度）
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.lg,
                  ),
                  // 卡片在屏上垂直居中：内容不足一屏时也居中，读起来稳定
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      VocabularyCard(
                        word: word,
                        onPlayWord: controller.playWord,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _PadReviewActions(
          onPrevious: controller.goPrevious,
          onIncorrect: controller.markIncorrect,
          onCorrect: controller.markCorrect,
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// 顶栏：返回 + 进度（第 N / 共 M）+ 录入生词。
///
/// 左端为系统「窗口控件」让位（[PadLayout.windowControlsLeftInset]，仅 iOS 非零）：
/// iPadOS 26+ 窗口化时左上角的「…」胶囊画在内容之上，会盖住返回键（实测）。
class _PadVocabularyTopBar extends StatelessWidget {
  const _PadVocabularyTopBar({
    required this.currentIndex,
    required this.totalCount,
    required this.onBack,
    required this.onAddWord,
  });

  final int currentIndex;
  final int totalCount;
  final VoidCallback onBack;
  final VoidCallback onAddWord;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm + PadLayout.windowControlsLeftInset,
        6,
        AppSpacing.sm,
        6,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            color: AppColors.mutedSoft,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '第 ${currentIndex + 1} / 共 $totalCount 个',
            style: AppType.textTheme.labelMedium
                ?.copyWith(color: AppColors.mutedSoft),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onAddWord,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('录入生词'),
          ),
        ],
      ),
    );
  }
}

/// 底部复习动作：上一个 / 不认识 / 认识。
class _PadReviewActions extends StatelessWidget {
  const _PadReviewActions({
    required this.onPrevious,
    required this.onIncorrect,
    required this.onCorrect,
  });

  final VoidCallback onPrevious;
  final VoidCallback onIncorrect;
  final VoidCallback onCorrect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: AppButton(
                  text: '上一个',
                  onClick: onPrevious,
                  variant: AppButtonVariant.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  text: '不认识',
                  onClick: onIncorrect,
                  variant: AppButtonVariant.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(text: '认识', onClick: onCorrect),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右侧统计栏：本次复习的进度与结果（大屏摊开，手机版在卡内/顶栏）。
class _PadReviewStats extends StatelessWidget {
  const _PadReviewStats({required this.state});

  final VocabularyUiState state;

  @override
  Widget build(BuildContext context) {
    final total = state.totalCount;
    final done = state.reviewedCount;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本轮复习', style: AppType.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Text(
            '$done / $total',
            style: AppType.textTheme.displayMedium
                ?.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '已认识 ${state.newlyKnownCount} 个',
            style: AppType.textTheme.bodyMedium
                ?.copyWith(color: AppColors.mutedSoft),
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              backgroundColor: AppColors.surfaceCard,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
