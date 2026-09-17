import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/components/article_card.dart';
import '../../core/components/loading_indicator.dart';
import '../../core/navigation/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import '../../data/auth/auth_service.dart';
import '../../di/providers.dart';
import 'home_controller.dart';

/// Home 页（对照 Kotlin HomeScreen.kt）：
/// - isLoading → LoadingIndicator
/// - HomeHeader（日期 + streak>0 时 StreakBadge）
/// - 同步中 → EmptyState（'文章同步中' + generationMessage 兜底文案）
/// - 空态 → EmptyState（'暂无文章'）
/// - 否则 → DayGroup 列表（今天/昨天/日期，可折叠，ArticleCard）
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.onArticleClick});

  /// 点击文章卡片 → 进入 Reading 页（路由层注入）。
  final ValueChanged<int> onArticleClick;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // 对照 Kotlin HomeViewModel.init：loadHome + observeSettingsForRefresh
    Future.microtask(() {
      ref.read(homeControllerProvider.notifier).load();
      ref.read(homeControllerProvider.notifier).observeSettingsForRefresh();
    });
    // 2026-08-12 修复：后台 worker isolate 用独立连接写库，UI 的 drift
    // watch 收不到变更通知（per-connection），生成完成的文章不会自动出现。
    // app 回到前台时重新读库（reloadWindow 保留已加载的分页窗口，不会把
    // 用户滚到的第 N 页截断回第 1 页）。AppLifecycleListener 只在状态变化时
    // 回调，首次启动（初始即 resumed）不会重复触发。
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        ref.read(homeControllerProvider.notifier).reloadWindow();
      },
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
      return const SizedBox.expand(child: LoadingIndicator());
    }

    // 下拉刷新：重跑同步编排（同步 + 今日分配）+ 回第 1 页；
    // AlwaysScrollableScrollPhysics 保证内容不满屏时也可下拉（含空态）。
    //
    // CustomScrollView + SliverList.builder（原为 ListView(children: [...]）：
    // 后者首帧就把全部日期分组的全部卡片都构建出来，历史越长越慢。
    return RefreshIndicator(
      onRefresh: () => ref.read(homeControllerProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
          // 服务端已配置但未登录 → 提示条 + 登录入口（本地模式不显示；
          // 服务端配置时守卫会拦截，此处是「暂不登录」回访入口）
          if (ref.watch(serverConfiguredProvider) &&
              ref.watch(authServiceProvider).status != AuthStatus.loggedIn)
            const SliverToBoxAdapter(child: _LoginBanner()),
          SliverToBoxAdapter(
            child:
                _HomeHeader(dateLabel: state.dateLabel, streak: state.streak),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
          ..._bodySlivers(state),
        ],
      ),
    );
  }

  /// 列表主体：同步中 / 空态，或分组列表 + 底部分页哨兵。
  List<Widget> _bodySlivers(HomeUiState state) {
    if (state.isGenerating) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            child: EmptyState(
              icon: Icons.settings_outlined,
              message: '文章同步中',
              subMessage: state.generationMessage.isEmpty
                  ? '同步失败，下拉重试'
                  : state.generationMessage,
            ),
          ),
        ),
      ];
    }
    if (state.articleGroups.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: AppSpacing.xxl),
            child: EmptyState(
              icon: Icons.menu_book_outlined,
              message: '暂无文章',
              // 2026-08-13（计划 B T5 carry / T6 落地）：同步模型下文章来自
              // 服务端，空态语义从「等待本地生成」改为「同步失败可重试」
              subMessage: '暂时没有文章，下拉刷新试试',
            ),
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        // 末尾多一项是分页哨兵。必须放进 SliverList 按需构建——若做成独立的
        // SliverToBoxAdapter，`slivers: [...]` 里的 widget 是首帧立即构建的，
        // 哨兵会一开始就触发 loadMore，把整段历史一次拉完（分页就白做了）。
        itemCount: state.articleGroups.length + 1,
        itemBuilder: (context, index) {
          if (index == state.articleGroups.length) {
            return _ListFooter(
              // key 随页数变化：新一页渲染后哨兵若仍在视口内，新实例会再续一页
              key: ValueKey('home-footer-${state.articleGroups.length}'),
              hasMore: state.hasMore,
              isLoadingMore: state.isLoadingMore,
              onLoadMore: () =>
                  ref.read(homeControllerProvider.notifier).loadMore(),
            );
          }
          final group = state.articleGroups[index];
          return Material(
            color: Colors.transparent,
            child: _DayGroup(
              key: ValueKey(group.dateLabel),
              dateLabel: group.dateLabel,
              articles: group.articles,
              collapsed: state.collapsedDates.contains(group.dateLabel),
              onToggle: () => ref
                  .read(homeControllerProvider.notifier)
                  .toggleDateGroup(group.dateLabel),
              onArticleClick: widget.onArticleClick,
            ),
          );
        },
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }
}

/// 顶部日期 + 连续天数胶囊（对照 Kotlin HomeHeader）。
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.dateLabel, required this.streak});

  final String dateLabel;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppPage.horizontalPadding,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(dateLabel, style: AppType.textTheme.titleMedium),
          if (streak > 0) _StreakBadge(streak: streak),
        ],
      ),
    );
  }
}

/// 连续学习天数胶囊（对照 Kotlin StreakBadge）。
class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            '连续 $streak 天',
            style: AppType.textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 按日期分组的文章列表（对照 Kotlin DayGroup）：
/// 可折叠日期头（展开时 ExpandLess / 收起时 ExpandMore），
/// 文章卡片垂直间距 8dp。
///
/// 折叠态由 [HomeUiState.collapsedDates] 托管（本组件无状态）：SliverList 会
/// dispose 滑出缓存区的子项，留在 State 里的折叠态一滚就丢。
class _DayGroup extends StatelessWidget {
  const _DayGroup({
    super.key,
    required this.dateLabel,
    required this.articles,
    required this.collapsed,
    required this.onToggle,
    required this.onArticleClick,
  });

  final String dateLabel;
  final List<ArticleItemUi> articles;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<int> onArticleClick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppPage.horizontalPadding,
          ),
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dateLabel, style: AppType.textTheme.titleMedium),
                  Icon(
                    // 箭头指向「点下去会发生什么」：收起时朝下（展开），
                    // 展开时朝上（收起）。原实现是反的。
                    collapsed
                        ? Icons.expand_more_outlined
                        : Icons.expand_less_outlined,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        // 回归修复：原实现的 _expanded 只换了图标，文章列无条件渲染 →
        // 点击日期头看着「没反应」。折叠时必须真的不构建文章列。
        if (!collapsed)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppPage.horizontalPadding,
            ),
            child: Column(
              children: [
                for (final article in articles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _ArticleCardView(
                      article: article,
                      onClick: () => onArticleClick(article.id),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

/// 列表底部：分页提示 + 加载哨兵。
///
/// 本组件被 build 出来即意味着已滑到列表末尾（SliverList 只构建视口附近的
/// 子项），因此在 initState 里排一帧触发 [onLoadMore]——顺带解决「首屏内容
/// 不满一屏」：那时哨兵一开始就可见，会自动继续取直到填满或到底。
/// 正在加载不能在 build 期间改状态，故用 post-frame 回调。
class _ListFooter extends StatefulWidget {
  const _ListFooter({
    super.key,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  State<_ListFooter> createState() => _ListFooterState();
}

class _ListFooterState extends State<_ListFooter> {
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
    final (text, showSpinner) = switch ((widget.isLoadingMore, widget.hasMore)) {
      (true, _) => ('加载中…', true),
      (false, true) => ('上拉加载更多', false),
      (false, false) => ('没有更多文章了', false),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showSpinner) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            text,
            style: AppType.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoft,
            ),
          ),
        ],
      ),
    );
  }
}

/// ArticleCard 组件桥接：UI 模型 → 组件数据。
class _ArticleCardView extends StatelessWidget {
  const _ArticleCardView({required this.article, required this.onClick});

  final ArticleItemUi article;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    return ArticleCard(
      article: ArticleCardData(
        id: article.id,
        title: article.title,
        description: article.description,
        difficultyLabel: article.difficultyLabel,
        categoryLabel: article.categoryLabel,
        isReadCompleted: article.isReadCompleted,
      ),
      onClick: onClick,
    );
  }
}

/// 未登录提示条 + 登录入口（服务端已配置且未登录时显示）。
class _LoginBanner extends StatelessWidget {
  const _LoginBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppPage.horizontalPadding,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 18, color: AppColors.muted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '未登录',
                  style: AppType.textTheme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push(Routes.login),
                child: const Text('登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
