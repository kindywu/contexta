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
    // app 回到前台时重新 load()（幂等：已分配则走 Ready 分支，重新订阅
    // 文章流并拿到当前值）。AppLifecycleListener 只在状态变化时回调，
    // 首次启动（初始即 resumed）不会重复触发。
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        ref.read(homeControllerProvider.notifier).load();
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

    // 下拉刷新：重跑同步编排（同步 + 今日分配）+ 重载文章流；
    // AlwaysScrollableScrollPhysics 保证内容不满屏时也可下拉（含空态）。
    return RefreshIndicator(
      onRefresh: () => ref.read(homeControllerProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: AppSpacing.sm),
          // 服务端已配置但未登录 → 提示条 + 登录入口（本地模式不显示；
          // 服务端配置时守卫会拦截，此处是「暂不登录」回访入口）
          if (ref.watch(serverConfiguredProvider) &&
              ref.watch(authServiceProvider).status != AuthStatus.loggedIn)
            const _LoginBanner(),
          _HomeHeader(dateLabel: state.dateLabel, streak: state.streak),
          const SizedBox(height: AppSpacing.sm),
          if (state.isGenerating)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.settings_outlined,
                message: '文章同步中',
                subMessage: state.generationMessage.isEmpty
                    ? '同步失败，下拉重试'
                    : state.generationMessage,
              ),
            )
          else if (state.articleGroups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.menu_book_outlined,
                message: '暂无文章',
                // 2026-08-13（计划 B T5 carry / T6 落地）：同步模型下文章来自
                // 服务端，空态语义从「等待本地生成」改为「同步失败可重试」
                subMessage: '暂时没有文章，下拉刷新试试',
              ),
            )
          else
            for (final group in state.articleGroups)
              Material(
                color: Colors.transparent,
                child: _DayGroup(
                  dateLabel: group.dateLabel,
                  articles: group.articles,
                  onArticleClick: widget.onArticleClick,
                ),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
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
/// 可折叠日期头（展开时 ExpandMore / 收起时 ExpandLess），
/// 文章卡片垂直间距 8dp。
class _DayGroup extends StatefulWidget {
  const _DayGroup({
    required this.dateLabel,
    required this.articles,
    required this.onArticleClick,
  });

  final String dateLabel;
  final List<ArticleItemUi> articles;
  final ValueChanged<int> onArticleClick;

  @override
  State<_DayGroup> createState() => _DayGroupState();
}

class _DayGroupState extends State<_DayGroup> {
  bool _expanded = true;

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
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.dateLabel, style: AppType.textTheme.titleMedium),
                  Icon(
                    _expanded
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
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppPage.horizontalPadding,
          ),
          child: Column(
            children: [
              for (final article in widget.articles)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _ArticleCardView(
                    article: article,
                    onClick: () => widget.onArticleClick(article.id),
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
