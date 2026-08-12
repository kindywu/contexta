import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/iso8601.dart';
import '../../di/providers.dart';
import '../../domain/background_work_scheduler.dart';
import '../../domain/generation/article_prompts.dart';
import '../../domain/model/article.dart';
import '../../domain/model/daily_learning_info.dart';
import '../../domain/model/user_settings.dart';
import '../../domain/repository/article_repository.dart';
import '../../domain/repository/settings_repository.dart';
import '../../domain/repository/stats_repository.dart';
import '../../domain/usecase/create_initial_batch_usecase.dart';
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
    this.generationErrors = const [],
  });

  final String dateLabel;
  final int streak;
  final List<ArticleGroupUi> articleGroups;
  final bool isLoading;
  final bool isGenerating;
  final String generationMessage;
  final List<ErrorUi> generationErrors;

  HomeUiState copyWith({
    String? dateLabel,
    int? streak,
    List<ArticleGroupUi>? articleGroups,
    bool? isLoading,
    bool? isGenerating,
    String? generationMessage,
    List<ErrorUi>? generationErrors,
  }) =>
      HomeUiState(
        dateLabel: dateLabel ?? this.dateLabel,
        streak: streak ?? this.streak,
        articleGroups: articleGroups ?? this.articleGroups,
        isLoading: isLoading ?? this.isLoading,
        isGenerating: isGenerating ?? this.isGenerating,
        generationMessage: generationMessage ?? this.generationMessage,
        generationErrors: generationErrors ?? this.generationErrors,
      );
}

class ErrorUi {
  const ErrorUi({
    required this.articleId,
    required this.errorCode,
    required this.errorMessage,
    required this.errorHelp,
    required this.canRetry,
  });

  final int articleId;
  final String errorCode;
  final String errorMessage;
  final String errorHelp;
  final bool canRetry;
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
/// - loadHome：日期头 + streak → startupOrch 三分支
/// - observeArticles：GetHomeArticlesUseCase 过滤（按用户难度 + 每日篇数
///   snapshot）+ 按日期分组；批次流 combine 后过滤空组
/// - observeErrors：生成错误 → ErrorUi（FAILED/TIMEOUT/FATAL 可重试）
/// - observeSettingsForRefresh：设置变更 → 重新观察文章流
class HomeController extends StateNotifier<HomeUiState> {
  HomeController({
    required this._articleRepository,
    required this._settingsRepository,
    required this._statsRepository,
    required this._startupOrch,
    required this._createInitialBatch,
    required this._getHomeArticles,
    required this._generationScheduler,
  }) : super(const HomeUiState());

  final ArticleRepository _articleRepository;
  final SettingsRepository _settingsRepository;
  final StatsRepository _statsRepository;
  final StartupOrchestrationUseCase _startupOrch;
  final CreateInitialBatchUseCase _createInitialBatch;
  final GetHomeArticlesUseCase _getHomeArticles;
  final BackgroundWorkScheduler _generationScheduler;

  StreamSubscription<void>? _errorsSub;
  StreamSubscription<UserSettings?>? _settingsSub;
  final _batchSubs = <int, StreamSubscription<List<Article>>>{};
  final _latestArticles = <int, List<Article>>{};
  List<DailyLearningInfo> _historyReads = const [];
  String _userDifficulty = 'MEDIUM';

  /// 主加载入口（Kotlin loadHome）：日期头 + streak + 启动编排。
  Future<void> load() async {
    state = state.copyWith(dateLabel: _dateLabel(DateTime.now()));

    final stats = await _statsRepository.getStats();
    state = state.copyWith(streak: stats?.currentStreak ?? 0);

    _observeErrors();

    final result = await _startupOrch(1);
    switch (result) {
      case StartupNeedsInitialBatch(
          difficulty: final difficulty,
          dailyCount: final dailyCount,
        ):
        state = state.copyWith(
          isGenerating: true,
          generationMessage: '正在准备文章…',
        );
        final batchId = await _createInitialBatch(difficulty, dailyCount);
        await _generationScheduler.scheduleBatchGeneration(batchId);
        await _observeArticles();
      case StartupReady():
        await _observeArticles();
      case StartupPipelineBlocked():
        state = state.copyWith(
          isLoading: false,
          generationMessage: '生成管道被阻塞，请联系技术支持',
        );
      case StartupNeedsOnboarding():
        state = state.copyWith(isLoading: false);
    }
  }

  void observeSettingsForRefresh() {
    _settingsSub?.cancel();
    _settingsSub = _settingsRepository.observeSettings().listen((_) {
      _observeArticles();
    });
  }

  void _observeErrors() {
    _errorsSub?.cancel();
    _errorsSub = _articleRepository.observeGenerationErrors().listen((errors) {
      state = state.copyWith(
        generationErrors: [
          for (final e in errors)
            ErrorUi(
              articleId: e.entityId,
              errorCode: e.errorCode,
              errorMessage: e.errorMessage,
              errorHelp: e.errorHelp ?? '',
              canRetry: e.status == 'FAILED' ||
                  e.status == 'TIMEOUT' ||
                  e.status == 'FATAL',
            ),
        ],
      );
    });
  }

  /// 观察历史阅读批次的文章流（Kotlin observeArticles）：
  /// 每个 daily_learning 批次一个 observeArticles 流，聚合后生成分组。
  Future<void> _observeArticles() async {
    for (final sub in _batchSubs.values) {
      await sub.cancel();
    }
    _batchSubs.clear();
    _latestArticles.clear();

    _historyReads = await _articleRepository.getAllDailyLearningInfos();
    if (_historyReads.isEmpty) {
      state = state.copyWith(isLoading: false);
      return;
    }

    final settings = await _settingsRepository.getSettings();
    _userDifficulty = settings?.difficultyLevel ?? 'MEDIUM';

    for (final readInfo in _historyReads) {
      final batchId = readInfo.batch.id;
      _batchSubs[batchId] =
          _articleRepository.observeArticles(batchId).listen((articles) {
        _latestArticles[batchId] = articles;
        _recomputeGroups();
      });
    }
    _recomputeGroups();
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
      groups.add(ArticleGroupUi(
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
      ));
    }

    final hasContent = groups.any((g) => g.articles.isNotEmpty);
    // 2026-08-12：今天有分配但今天的组为空（文章未生成完成/被过滤）时，
    // 即使昨天/更早有组也显示"生成中"，避免今天静默缺失。
    final todayIso = isoLocalDate(DateTime.now());
    final todayRead = _historyReads.any((r) => r.learningDate == todayIso);
    final todayGroupShown = groups.any((g) => g.dateLabel == '今天');
    final todayPending = todayRead && !todayGroupShown;

    state = state.copyWith(
      articleGroups: groups,
      isLoading: false,
      isGenerating: todayPending || !hasContent,
      generationMessage:
          (todayPending || !hasContent) ? '文章生成中，请稍候…' : '',
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
    _errorsSub?.cancel();
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
    createInitialBatch: ref.watch(createInitialBatchUseCaseProvider),
    getHomeArticles: ref.watch(getHomeArticlesUseCaseProvider),
    generationScheduler: ref.watch(backgroundWorkSchedulerProvider),
  );
});
