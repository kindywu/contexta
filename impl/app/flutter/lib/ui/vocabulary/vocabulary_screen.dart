import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/components/app_button.dart';
import '../../core/components/app_card.dart';
import '../../core/components/loading_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import 'vocabulary_controller.dart';

/// Vocabulary 页（对照 Kotlin VocabularyScreen.kt）：
/// - 顶栏：返回 + 进度点（当前/总数 + 分段条）+ 录入单词
/// - 复习卡：词头 30sp serif + 音标 + 发音钮 + 按词性分块义项
///   （词性珊瑚 + 中文义 + 英文定义 + example 小节）+ 认识次数
/// - 右下 56dp 圆形 ✓ FAB（标记认识）；滑动切换单词（goNext/goPrevious）
/// - 生词表为空 → EmptyState；全部复习完 → 总结页（Celebration +
///   复习单词数/新标记认识数 + 再来一轮）
///
/// 对照 Kotlin 的 fling 边界切换（CardSwitchNestedScroll）：Flutter 用
/// `NotificationListener<OverscrollIndicatorNotification>` + 滚动控制器
/// 边界检测近似实现。
class VocabularyScreen extends ConsumerStatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.onBack,
    required this.onAddWord,
  });

  final VoidCallback onBack;
  final VoidCallback onAddWord;

  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vocabularyControllerProvider);
    final controller = ref.read(vocabularyControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // 顶栏：返回 + 进度 + 录入
          _VocabularyAppBar(
            totalCount: state.totalCount,
            currentIndex: state.currentIndex,
            isSummary: state.isSummary,
            onBack: widget.onBack,
            onAddWord: widget.onAddWord,
          ),
          Expanded(
            child: switch ((state.isLoading, state.isSummary)) {
              (true, _) => const LoadingIndicator(),
              (false, true) => _VocabularySummary(
                  reviewedCount: state.reviewedCount,
                  newlyKnownCount: state.newlyKnownCount,
                  onRestart: controller.restart,
                ),
              (false, false) when state.totalCount == 0 => const EmptyState(
                  icon: Icons.edit_note_outlined,
                  message: '生词表为空',
                  subMessage: '阅读时点击单词可加入生词表',
                ),
              (false, false) => _buildCard(state, controller),
            },
          ),
        ],
      ),
    );
  }

  /// 复习卡 + 边界滑动切换 + ✓ FAB。
  Widget _buildCard(VocabularyUiState state, VocabularyController controller) {
    final word = state.currentWord;
    if (word == null) {
      return const SizedBox.shrink();
    }
    final card = VocabularyCard(
      word: word,
      onPlayWord: controller.playWord,
    );
    final scroll = SingleChildScrollView(
      controller: _scrollController,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            card,
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: (notification) {
        // 顶/底边界 overscroll：切换单词（近似 Kotlin fling 切换）
        if (notification.leading) {
          controller.goPrevious();
        } else {
          controller.goNext();
        }
        return true;
      },
      child: Stack(
        children: [
          scroll,
          // ✓ FAB：右下 56dp 圆形
          Positioned(
            right: 20,
            bottom: 20,
            child: Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: controller.markCorrect,
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(
                    Icons.check,
                    color: AppColors.onPrimary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏：返回 + 进度（当前/总数 + 分段条）+ 录入单词。
class _VocabularyAppBar extends StatelessWidget {
  const _VocabularyAppBar({
    required this.totalCount,
    required this.currentIndex,
    required this.isSummary,
    required this.onBack,
    required this.onAddWord,
  });

  final int totalCount;
  final int currentIndex;
  final bool isSummary;
  final VoidCallback onBack;
  final VoidCallback onAddWord;

  @override
  Widget build(BuildContext context) {
    final showProgress = !isSummary && totalCount > 0;
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back,
            tooltip: '返回',
            onClick: onBack,
            tint: AppColors.mutedSoft,
          ),
          const Spacer(),
          if (showProgress) ...[
            _ProgressDots(current: currentIndex + 1, total: totalCount),
            const Spacer(),
          ],
          AppIconButton(
            icon: Icons.add,
            tooltip: '录入单词',
            onClick: onAddWord,
            tint: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// 进度：'当前 / 总数' + 分段条（当前段 Primary 16dp 圆角，已完成 40%
/// Muted，未完成 Hairline 圆形）。
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$current / $total',
          style: AppType.textTheme.labelMedium
              ?.copyWith(color: AppColors.mutedSoft),
        ),
        const SizedBox(width: 8),
        for (final step in List.generate(total, (i) => i + 1)) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 6,
            width: step == current ? 16 : 6,
            decoration: BoxDecoration(
              color: step == current
                  ? AppColors.primary
                  : step < current
                      ? AppColors.muted.withValues(alpha: 0.4)
                      : AppColors.hairline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    );
  }
}

/// 复习卡（对照 Kotlin VocabularyCard）。
class VocabularyCard extends StatelessWidget {
  const VocabularyCard({
    super.key,
    required this.word,
    required this.onPlayWord,
  });

  final VocabCardData word;
  final VoidCallback onPlayWord;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 词头 30sp serif
          Text(
            word.word,
            textAlign: TextAlign.center,
            style: AppType.textTheme.headlineLarge
                ?.copyWith(fontSize: 30, color: AppColors.ink),
          ),
          if (word.phonetic != null) ...[
            const SizedBox(height: 4),
            Text(
              word.phonetic!,
              textAlign: TextAlign.center,
              style: AppType.phonetic.copyWith(fontSize: 15),
            ),
          ],
          const SizedBox(height: 8),
          // 发音钮
          Center(
            child: AppIconButton(
              icon: Icons.volume_up_outlined,
              tooltip: '发音',
              onClick: onPlayWord,
              size: 36,
              tint: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          // 词性块
          for (final sense in word.senses) ...[
            _SenseBlock(sense: sense),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          // 认识次数
          Text(
            '已认识 ${word.reviewStreak}/${word.masteryThreshold} 次',
            textAlign: TextAlign.center,
            style: AppType.textTheme.labelMedium
                ?.copyWith(color: AppColors.mutedSoft),
          ),
        ],
      ),
    );
  }
}

/// 词性块：SurfaceSoft 底 + 12dp 圆角（对照 Kotlin SenseBlock）。
class _SenseBlock extends StatelessWidget {
  const _SenseBlock({required this.sense});

  final VocabSenseData sense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 词性 + 中文义
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sense.partOfSpeech,
                style: AppType.textTheme.labelLarge
                    ?.copyWith(color: AppColors.primary),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sense.chineseMeaning,
                  style: AppType.textTheme.headlineSmall
                      ?.copyWith(color: AppColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            sense.englishDefinition,
            style: AppType.textTheme.bodySmall
                ?.copyWith(fontSize: 15, color: AppColors.muted),
          ),
          if (sense.examples.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'example',
              style: AppType.textTheme.labelLarge
                  ?.copyWith(color: AppColors.primary),
            ),
            for (final example in sense.examples) ...[
              const SizedBox(height: 4),
              Text(
                example.sentenceEn,
                style: AppType.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 2),
              Text(
                example.sentenceZh,
                style: AppType.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 复习完成总结（对照 Kotlin VocabularySummary）：Celebration +
/// 卡片内两个统计 + 再来一轮。
class _VocabularySummary extends StatelessWidget {
  const _VocabularySummary({
    required this.reviewedCount,
    required this.newlyKnownCount,
    required this.onRestart,
  });

  final int reviewedCount;
  final int newlyKnownCount;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.celebration_outlined,
            color: AppColors.success,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            '复习完成！',
            style: AppType.textTheme.headlineLarge
                ?.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: 24),
          AppCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _SummaryStat(value: reviewedCount.toString(), label: '复习单词'),
                const SizedBox(height: 16),
                _SummaryStat(
                    value: newlyKnownCount.toString(), label: '新标记认识'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          AppButton(text: '再来一轮', onClick: onRestart),
        ],
      ),
    );
  }
}

/// 统计项：数字（Primary headlineMedium）+ 标签（Muted bodyMedium）。
class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppType.textTheme.headlineMedium
              ?.copyWith(color: AppColors.primary),
        ),
        Text(
          label,
          style: AppType.textTheme.bodyMedium
              ?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}
