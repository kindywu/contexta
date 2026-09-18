import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_type.dart';
import '../ui/home/home_controller.dart';
import 'pad_article_grid.dart';
import 'pad_continue_card.dart';
import 'pad_date_index.dart';
import 'pad_layout.dart';

/// 平板首页：**目录 + 内容两栏**（平板专属页面，与手机 `HomeScreen` 各自
/// 独立渲染，互不影响）。
///
/// 结构（本机 1280×800dp 横屏）：
///
/// ```text
/// ┌────────┬──────────────────────────────────────────────────────┐
/// │ 侧边栏  │ 日期 + 连续天数                                        │
/// │ 208dp  ├────────────┬─────────────────────────────────────────┤
/// │        │ 阅读记录    │ 今日推荐 / 继续阅读（Hero：真实开头段）    │
/// │        │ 今天  3/5  ├─────────────────────────────────────────┤
/// │        │ 昨天  5/5  │ 卡片网格（3 列 × 封面式卡片）             │
/// │        │ 8月11日    │                                         │
/// └────────┴────────────┴─────────────────────────────────────────┘
/// ```
///
/// 三处是**横屏才成立**的设计（手机竖屏做不了）：
/// 1. Hero 卡同时放得下"真实英文开头段 + 元信息 + 入口"，让"读哪篇"在首页
///    就决策完；
/// 2. 日期从"滚动经过的分组标题"变成常驻左栏目录，带 `3/5` 进度，点选即
///    筛选右侧网格；
/// 3. 卡片铺成封面式网格，靠色块扫视，而不是逐行读标题。
///
/// 复用的只有**数据层**（`homeControllerProvider` 的加载 / 分页 / 折叠状态
/// 机）；本页所有渲染都是 pad 自有实现，不引用手机侧任何组件。
class PadHomeScreen extends ConsumerStatefulWidget {
  const PadHomeScreen({super.key, required this.onArticleClick});

  final ValueChanged<int> onArticleClick;

  @override
  ConsumerState<PadHomeScreen> createState() => _PadHomeScreenState();
}

class _PadHomeScreenState extends ConsumerState<PadHomeScreen> {
  late final AppLifecycleListener _lifecycleListener;

  /// 当前选中的日期标签（null = 尚未选过，跟随数据取最新一天）。
  String? _selectedDate;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(homeControllerProvider.notifier).load();
      ref.read(homeControllerProvider.notifier).observeSettingsForRefresh();
    });
    // 后台 worker 用独立连接写库，UI 的 drift watch 收不到通知 —— 回前台重读
    _lifecycleListener = AppLifecycleListener(
      onResume: () => ref.read(homeControllerProvider.notifier).reloadWindow(),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeControllerProvider);

    if (state.isLoading) {
      return const Center(child: _PadLoading());
    }

    // 选中日期跟随数据：选过的那天还在就保持，不在了（换页/筛选后消失）
    // 就回落到最新一天。放在 build 里算而不是存 state，避免多一次同步。
    final groups = state.articleGroups;
    final selected = groups.any((g) => g.dateLabel == _selectedDate)
        ? _selectedDate
        : groups.firstOrNull?.dateLabel;
    final selectedGroup = groups
        .where((g) => g.dateLabel == selected)
        .firstOrNull;
    final recommended = _recommendedArticle(groups);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PadHomeHeader(dateLabel: state.dateLabel, streak: state.streak),
        Expanded(
          child: switch (state) {
            HomeUiState(isGenerating: true) => const Center(
              child: _PadEmptyState(
                icon: Icons.sync_outlined,
                message: '文章同步中',
                subMessage: '稍等片刻，完成后自动出现',
              ),
            ),
            HomeUiState(articleGroups: []) => const Center(
              child: _PadEmptyState(
                icon: Icons.menu_book_outlined,
                message: '暂无文章',
                subMessage: '下拉刷新试试',
              ),
            ),
            _ => _body(
              state: state,
              groups: groups,
              selectedDate: selected,
              selectedGroup: selectedGroup,
              recommended: recommended,
            ),
          },
        ),
      ],
    );
  }

  /// 推荐阅读 = 选中日期里第一篇未读；整组读完则取该组第一篇。
  ArticleItemUi? _recommendedArticle(List<ArticleGroupUi> groups) {
    final all = [for (final g in groups) ...g.articles];
    return all.where((a) => !a.isReadCompleted).firstOrNull ?? all.firstOrNull;
  }

  Widget _body({
    required HomeUiState state,
    required List<ArticleGroupUi> groups,
    required String? selectedDate,
    required ArticleGroupUi? selectedGroup,
    required ArticleItemUi? recommended,
  }) {
    final articles = selectedGroup?.articles ?? const <ArticleItemUi>[];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左栏：常驻日期目录（内容多时自己滚）
        Padding(
          padding: const EdgeInsets.only(
            left: PadLayout.pagePadding,
            top: AppSpacing.md,
            bottom: AppSpacing.xl,
          ),
          child: SingleChildScrollView(
            child: PadDateIndex(
              groups: groups,
              selectedDate: selectedDate,
              onSelect: (label) => setState(() => _selectedDate = label),
            ),
          ),
        ),
        const SizedBox(width: PadLayout.dateIndexGap),
        // 右栏：Hero + 网格（滚动区）
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(homeControllerProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (recommended != null)
                  SliverToBoxAdapter(
                    child: PadContinueCard(
                      key: ValueKey('pad-hero-${recommended.id}'),
                      article: recommended,
                      onStart: widget.onArticleClick,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: PadLayout.pagePadding,
                      bottom: AppSpacing.md,
                    ),
                    child: _SectionHeader(
                      dateLabel: selectedDate ?? '',
                      articles: articles,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: PadLayout.pagePadding,
                    ),
                    child: PadArticleGrid(
                      articles: articles,
                      onArticleClick: widget.onArticleClick,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PadListFooter(
                    key: ValueKey('pad-home-footer-${groups.length}'),
                    hasMore: state.hasMore,
                    isLoadingMore: state.isLoadingMore,
                    onLoadMore: () =>
                        ref.read(homeControllerProvider.notifier).loadMore(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 顶部：日期 + 连续天数。
class _PadHomeHeader extends StatelessWidget {
  const _PadHomeHeader({required this.dateLabel, required this.streak});

  final String dateLabel;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: PadLayout.pagePadding,
        right: PadLayout.pagePadding,
        top: AppSpacing.xl,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            dateLabel,
            style: AppType.textTheme.displayMedium?.copyWith(
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          if (streak > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '🔥 连续 $streak 天',
                style: AppType.textTheme.labelMedium?.copyWith(
                  color: AppColors.bodyText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 网格区标题：选中日期 + 该日进度。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.dateLabel, required this.articles});

  final String dateLabel;
  final List<ArticleItemUi> articles;

  @override
  Widget build(BuildContext context) {
    final read = articles.where((a) => a.isReadCompleted).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          dateLabel,
          style: AppType.textTheme.headlineSmall?.copyWith(
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${articles.length} 篇 · 已读 $read',
          style: AppType.textTheme.bodySmall?.copyWith(
            color: AppColors.mutedSoft,
          ),
        ),
      ],
    );
  }
}

class _PadLoading extends StatelessWidget {
  const _PadLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(
        color: AppColors.primary,
        strokeWidth: 3,
      ),
    );
  }
}

/// pad 自有空态（图标 + 标题 + 副文案）。
class _PadEmptyState extends StatelessWidget {
  const _PadEmptyState({
    required this.icon,
    required this.message,
    required this.subMessage,
  });

  final IconData icon;
  final String message;
  final String subMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: AppColors.hairline),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          style: AppType.textTheme.titleMedium?.copyWith(
            color: AppColors.bodyText,
          ),
        ),
        if (subMessage.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subMessage,
            style: AppType.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoft,
            ),
          ),
        ],
      ],
    );
  }
}

/// 底部分页哨兵（滚到即取下一页）。
class _PadListFooter extends StatefulWidget {
  const _PadListFooter({
    super.key,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  State<_PadListFooter> createState() => _PadListFooterState();
}

class _PadListFooterState extends State<_PadListFooter> {
  @override
  void initState() {
    super.initState();
    if (!widget.hasMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.hasMore) return;
      widget.onLoadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasMore) return const SizedBox(height: AppSpacing.xl);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(child: _PadLoading()),
    );
  }
}
