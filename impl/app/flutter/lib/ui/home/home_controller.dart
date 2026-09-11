import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/iso8601.dart';
import '../../di/providers.dart';
import '../../domain/generation/article_prompts.dart';
import '../../domain/model/article.dart';
import '../../domain/model/daily_learning_info.dart';
import '../../domain/model/user_settings.dart';
import '../../domain/repository/article_repository.dart';
import '../../domain/repository/settings_repository.dart';
import '../../domain/repository/stats_repository.dart';
import '../../domain/usecase/get_home_articles_usecase.dart';
import '../../domain/usecase/startup_orchestration_usecase.dart';

/// Home 页 UI 状态（对照 Kotlin HomeUiState）。
class HomeUiState {
  const HomeUiState({
    this.dateLabel = '',
    this.streak = 0,
    this.articleGroups = const [],
    this.isLoading = true,
    this.isGenerating = false,
    this.generationMessage = '',
    this.hasMore = false,
    this.isLoadingMore = false,
    this.collapsedDates = const {},
  });

  final String dateLabel;
  final int streak;
  final List<ArticleGroupUi> articleGroups;
  final bool isLoading;
  final bool isGenerating;
  final String generationMessage;

  /// 还有更早的阅读记录未加载（底部提示：「上拉加载更多」/「没有更多文章了」）。
  final bool hasMore;

  /// 正在取下一页（底部提示显示「加载中…」）。
  final bool isLoadingMore;

  /// 已折叠的日期分组标签（今天/昨天/2026年8月1日）。
  ///
  /// 折叠态放这里而不是 `_DayGroup` 的 State 里：列表换成 SliverList.builder
  /// 后子项滑出缓存区会被 dispose，留在 State 里的折叠态一滚就丢。
  final Set<String> collapsedDates;

  HomeUiState copyWith({
    String? dateLabel,
    int? streak,
    List<ArticleGroupUi>? articleGroups,
    bool? isLoading,
    bool? isGenerating,
    String? generationMessage,
    bool? hasMore,
    bool? isLoadingMore,
    Set<String>? collapsedDates,
  }) => HomeUiState(
    dateLabel: dateLabel ?? this.dateLabel,
    streak: streak ?? this.streak,
    articleGroups: articleGroups ?? this.articleGroups,
    isLoading: isLoading ?? this.isLoading,
    isGenerating: isGenerating ?? this.isGenerating,
    generationMessage: generationMessage ?? this.generationMessage,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    collapsedDates: collapsedDates ?? this.collapsedDates,
  );
}

class ArticleGroupUi {
  const ArticleGroupUi({required this.dateLabel, required this.articles});

  final String dateLabel;
  final List<ArticleItemUi> articles;
}

class ArticleItemUi {
  const ArticleItemUi({
    required this.id,
    required this.title,
    required this.description,
    required this.difficultyLabel,
    required this.categoryLabel,
    this.isReadCompleted = false,
  });

  final int id;
  final String? title;
  final String description;
  final String difficultyLabel;
  final String categoryLabel;
  final bool isReadCompleted;
}

/// Home 页控制器（对照 Kotlin HomeViewModel）：
/// - loadHome：日期头 + streak → startupOrch 分支（同步模型）+ 第 1 页文章流
/// - refresh：下拉刷新 → 重跑同步编排 + 回第 1 页（幂等）
/// - loadMore：滚动到底 → keyset 追加下一页
/// - reloadWindow：回前台 / 设置变更 → **保持已加载窗口**重读
/// - 分组：GetHomeArticlesUseCase 过滤（按用户难度 + 每日篇数 snapshot）
///   + 按日期分组；批次流聚合后过滤空组
/// - toggleDateGroup：日期分组折叠态（放 UI state，理由见 HomeUiState 注释）
///
/// **分页**：首屏只读 [pageSize] 天 `daily_learning` 并只订阅这些批次的文章流
/// ——「历史越长首屏越慢」由此消除（改造前一次读全部历史 + 每天一个订阅）。
/// 往下滚一页追加一页。
///
/// 2026-08-13（计划 B Task 6）：observeErrors（生成错误订阅）随本地生成
/// 管道删除——generationErrors/ErrorUi 状态与 UI 一并移除。
class HomeController extends StateNotifier<HomeUiState> {
  HomeController({
    required this._articleRepository,
    required this._settingsRepository,
    required this._statsRepository,
    required this._startupOrch,
    required this._getHomeArticles,
  }) : super(const HomeUiState());

  /// 一页的天数（= `daily_learning` 记录数）。用户裁定：首屏 3 个批次即可。
  static const pageSize = 3;

  final ArticleRepository _articleRepository;
  final SettingsRepository _settingsRepository;
  final StatsRepository _statsRepository;
  final StartupOrchestrationUseCase _startupOrch;
  final GetHomeArticlesUseCase _getHomeArticles;

  StreamSubscription<UserSettings?>? _settingsSub;
  final _batchSubs = <int, StreamSubscription<List<Article>>>{};
  final _latestArticles = <int, List<Article>>{};

  /// 已加载的阅读记录窗口（learning_date 降序，最新在前）。
  List<DailyLearningInfo> _historyReads = const [];

  /// 是否还有更早的记录未加载（`hasMore` 状态的来源）。
  bool _hasMore = false;

  String _userDifficulty = 'MEDIUM';

  /// 主加载入口（Kotlin loadHome）：日期头 + streak + 启动编排 + 第 1 页。
  Future<void> load() async {
    state = state.copyWith(dateLabel: _dateLabel(DateTime.now()));

    final stats = await _statsRepository.getStats();
    state = state.copyWith(streak: stats?.currentStreak ?? 0);

    final result = await _startupOrch();
    switch (result) {
      // 未 onboarding：等引导页接管，首页仅收尾 loading
      case StartupNeedsOnboarding():
        state = state.copyWith(isLoading: false);
      // 未登录：同步跳过，本地文章照常加载（横幅提供登录入口）
      case StartupNeedsLogin():
        await _loadFirstPage();
      // 同步已执行（失败则 syncedBatches=0）：正常加载本地文章
      case StartupReady():
        await _loadFirstPage();
    }
  }

  /// 下拉刷新：重跑启动编排（同步 + 今日分配，幂等——已分配过不重复）
  /// 并回到第 1 页。
  Future<void> refresh() async {
    await _startupOrch();
    await _loadFirstPage();
  }

  /// 回前台重载（AppLifecycleListener.onResume）：后台 worker 用独立连接写库，
  /// UI 的 drift watch 收不到变更通知，必须重读；但**保持已加载的窗口**——
  /// 否则用户滚到第 N 页切个后台回来会被截断回第 1 页。
  Future<void> reloadWindow() => _readWindow(resubscribeAll: true);

  /// 滚动到底：按游标追加下一页。到底 / 正在加载时是 no-op。
  Future<void> loadMore() async {
    if (!_hasMore || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true);
    await _appendPage();
    state = state.copyWith(isLoadingMore: false);
  }

  /// 折叠 / 展开某个日期分组（标签 = 今天 / 昨天 / 2026年8月1日）。
  void toggleDateGroup(String dateLabel) {
    final next = Set<String>.of(state.collapsedDates);
    if (!next.remove(dateLabel)) next.add(dateLabel);
    state = state.copyWith(collapsedDates: next);
  }

  void observeSettingsForRefresh() {
    _settingsSub?.cancel();
    _settingsSub = _settingsRepository.observeSettings().listen((_) {
      _readWindow(resubscribeAll: true);
    });
  }

  /// 首次加载 / 下拉刷新：窗口回到第 1 页。
  Future<void> _loadFirstPage() async {
    _historyReads = const [];
    await _syncUserDifficulty();
    await _appendPage();
    // 首屏补页：第 1 页（最新 3 天）没有可展示文章但还有更早记录时继续取，
    // 保住「有内容就展示」的语义——否则用户看到空态，尽管更早的日子有文章。
    // 终止条件与改造前一致（最多读到没有更多为止）。
    while (state.articleGroups.isEmpty && _hasMore) {
      await _appendPage();
    }
  }

  /// 读下一页并追加到窗口（窗口为空时即第 1 页）。
  ///
  /// 以窗口最后一条日期为游标；`limit + 1` 取回后多出一条即表示还有更多
  /// ——省一次 COUNT。
  Future<void> _appendPage() async {
    final cursor =
        _historyReads.isEmpty ? null : _historyReads.last.learningDate;
    final fetched = await _articleRepository.getDailyLearningInfosPage(
      beforeDate: cursor,
      limit: pageSize + 1,
    );
    _hasMore = fetched.length > pageSize;
    final page = _hasMore ? fetched.sublist(0, pageSize) : fetched;
    _historyReads = [..._historyReads, ...page];

    await _subscribeWindow(resubscribeAll: false);
    _recomputeGroups();
  }

  /// 重读当前窗口（保持已加载天数）并重建订阅。回前台 / 设置变更用。
  Future<void> _readWindow({required bool resubscribeAll}) async {
    await _syncUserDifficulty();
    // 至少保留一页：窗口还没建立时（首次 load 前的 onResume）按第 1 页读
    final keep =
        _historyReads.length < pageSize ? pageSize : _historyReads.length;
    final fetched =
        await _articleRepository.getDailyLearningInfosPage(limit: keep + 1);
    _hasMore = fetched.length > keep;
    _historyReads = _hasMore ? fetched.sublist(0, keep) : fetched;

    await _subscribeWindow(resubscribeAll: resubscribeAll);
    _recomputeGroups();
  }

  Future<void> _syncUserDifficulty() async {
    final settings = await _settingsRepository.getSettings();
    _userDifficulty = settings?.difficultyLevel ?? 'MEDIUM';
  }

  /// 订阅窗口内批次的文章流。
  ///
  /// [resubscribeAll] 为 true 时连已订阅批次一起重建：后台 worker 用独立连接
  /// 写库，旧订阅收不到变更，重新 watch 才能读到最新数据（2026-08-12 修复的
  /// 原始问题）。为 false 时只补订阅新进窗口的批次，已订阅的不动——滚动加载
  /// 下一页时不重建整列。掉出窗口的批次退订并丢弃缓存。
  Future<void> _subscribeWindow({required bool resubscribeAll}) async {
    final wanted = {for (final read in _historyReads) read.batch.id};

    for (final batchId in _batchSubs.keys.toList()) {
      final stays = wanted.contains(batchId);
      if (stays && !resubscribeAll) continue;
      await _batchSubs.remove(batchId)?.cancel();
      if (!stays) _latestArticles.remove(batchId);
    }

    for (final batchId in wanted) {
      if (_batchSubs.containsKey(batchId)) continue;
      _batchSubs[batchId] = _articleRepository.observeArticles(batchId).listen((
        articles,
      ) {
        _latestArticles[batchId] = articles;
        _recomputeGroups();
      });
    }
  }

  /// 聚合当前所有批次的最新文章，生成按日期排序的分组列表
  /// （Kotlin combine 过滤空组 + hasContent 语义）。
  void _recomputeGroups() {
    final groups = <ArticleGroupUi>[];
    for (final readInfo in _historyReads) {
      final batchId = readInfo.batch.id;
      final articles = _latestArticles[batchId];
      if (articles == null) continue;
      final shown = _getHomeArticles(
        articles,
        _userDifficulty,
        readInfo.dailyCountSnapshot,
      );
      if (shown.isEmpty) continue;
      groups.add(
        ArticleGroupUi(
          dateLabel: _dateLabelFor(readInfo.learningDate),
          articles: [
            for (final article in shown)
              ArticleItemUi(
                id: article.id,
                title: article.title,
                description: article.contentCategory,
                difficultyLabel: _difficultyLabel(article.contentCategory),
                categoryLabel: article.contentCategory.replaceAll('_', ' '),
                isReadCompleted: article.readCompletedAt != null,
              ),
          ],
        ),
      );
    }

    final hasContent = groups.any((g) => g.articles.isNotEmpty);
    // 2026-08-14（计划 B T8 carry）：同步模型下文章来自服务端，文案改
    // 同步语义——今天有分配但今天的组为空（文章未同步完成/被过滤）时，
    // 即使昨天/更早有组也显示"同步中"，避免今天静默缺失。
    final todayIso = isoLocalDate(DateTime.now());
    // 窗口按日期降序且不含未来日期 → 今天有记录必然在窗口首位。
    // （改造前是 any(== today)：分页后只看已加载窗口，此处等价。）
    final todayRead = _historyReads.isNotEmpty &&
        _historyReads.first.learningDate == todayIso;
    final todayGroupShown = groups.any((g) => g.dateLabel == '今天');
    final todayPending = todayRead && !todayGroupShown;
    // 一条阅读记录都没有（从未分配过）→ 不是「同步中」，而是真的空
    // （UI 落「暂无文章」+ 下拉刷新）。有记录却展示不出文章才是同步未完成。
    final isGenerating =
        _historyReads.isNotEmpty && (todayPending || !hasContent);

    state = state.copyWith(
      articleGroups: groups,
      isLoading: false,
      isGenerating: isGenerating,
      generationMessage: isGenerating ? '文章同步中…' : '',
      hasMore: _hasMore,
    );
  }

  /// 难度徽标（对照 Kotlin ArticleCard 的 badge variant 映射：
  /// LOW → CET4、MEDIUM → CET6、HIGH → 专八；ArticleCard 的 variant
  /// switch 落在 else 分支渲染 Default）。
  static String _difficultyLabel(String category) =>
      switch (categoryToDifficulty(category)) {
        'LOW' => 'CET4',
        'MEDIUM' => 'CET6',
        'HIGH' => '专八',
        _ => 'CET6',
      };

  static const _weekdayNames = ['日', '一', '二', '三', '四', '五', '六'];

  /// 首页头部日期（Kotlin loadHome：星期用 `dayOfWeek.value % 7` 索引）。
  static String _dateLabel(DateTime now) =>
      '${now.year}年${now.month}月${now.day}日 星期${_weekdayNames[now.weekday % 7]}';

  /// 分组日期标签（Kotlin dateLabelFor：今天/昨天/全日期）。
  static String _dateLabelFor(String readDate) {
    final date = DateTime.parse('${readDate}T00:00:00');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (d == today) return '今天';
    if (d == yesterday) return '昨天';
    return '${date.year}年${date.month}月${date.day}日';
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    for (final sub in _batchSubs.values) {
      sub.cancel();
    }
    _batchSubs.clear();
    super.dispose();
  }
}

/// Home 控制器 Provider。
final homeControllerProvider =
    StateNotifierProvider<HomeController, HomeUiState>((ref) {
      return HomeController(
        articleRepository: ref.watch(articleRepositoryProvider),
        settingsRepository: ref.watch(settingsRepositoryProvider),
        statsRepository: ref.watch(statsRepositoryProvider),
        startupOrch: ref.watch(startupOrchestrationUseCaseProvider),
        getHomeArticles: ref.watch(getHomeArticlesUseCaseProvider),
      );
    });
