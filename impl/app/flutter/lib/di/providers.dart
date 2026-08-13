import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/navigation/app_router.dart';
import '../core/time/iso8601.dart';
import '../data/auth/auth_service.dart';
import '../data/auth/device_id_provider.dart';
import '../data/auth/native_phone_reader.dart';
import '../data/background/generation_scheduler.dart';
import '../data/local/database_open.dart';
import '../data/local/daos/article_daos.dart';
import '../data/local/daos/settings_daos.dart';
import '../data/local/daos/word_daos.dart';
import '../data/remote/article_api.dart';
import '../data/remote/deepseek_api.dart';
import '../data/remote/llm_caller.dart';
import '../data/remote/server_api_client.dart';
import '../data/sync/sync_articles_usecase.dart';
import '../data/repository/article_repository_impl.dart';
import '../data/repository/settings_repository_impl.dart';
import '../data/repository/stats_repository_impl.dart';
import '../data/repository/vocabulary_repository_impl.dart';
import '../data/repository/word_repository_impl.dart';
import '../data/tts/tts_cache_manager.dart';
import '../data/tts/tts_engine_factory.dart';
import '../domain/app_info_provider.dart';
import '../domain/background_work_scheduler.dart';
import '../domain/developer_alert_sender.dart';
import '../domain/llm_client.dart';
import '../domain/repository/article_repository.dart';
import '../domain/repository/settings_repository.dart';
import '../domain/repository/stats_repository.dart';
import '../domain/repository/vocabulary_repository.dart';
import '../domain/model/tts_voice.dart';
import '../domain/repository/word_repository.dart';
import '../domain/time/time_provider.dart';
import '../domain/tts/tts_engine.dart';
import '../domain/usecase/activate_seed_batch_usecase.dart';
import '../domain/usecase/add_word_usecase.dart';
import '../domain/usecase/create_initial_batch_usecase.dart';
import '../domain/usecase/generate_articles_usecase.dart';
import '../domain/usecase/get_home_articles_usecase.dart';
import '../domain/usecase/resend_pending_alerts_usecase.dart';
import '../domain/usecase/startup_orchestration_usecase.dart';
import '../domain/usecase/trigger_next_batch_usecase.dart';
import '../data/local/database.dart';
import '../data/monitoring/feishu_alert_sender.dart';

/// 数据库（生产路径：打开时 onCreate 建表 + 种子写入）。
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await buildAppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 服务端是否已配置（SERVER_BASE_URL 非空）。
/// 空 → App 全本地模式：登录页显示配置提示，路由不做登录拦截。测试可 override。
final serverConfiguredProvider =
    Provider<bool>((ref) => AppConfig.serverBaseUrl.isNotEmpty);

/// 服务端 API 客户端（认证拦截每次请求从 user_settings 读 token；
/// 登录/登出/同步共用同一实例——T2 遗留：token 变化自动重置 401 去重）。
final serverApiClientProvider = Provider<ServerApiClient>((ref) {
  final dio = Dio(BaseOptions(
    // 登录 / 同步接口较短：连接 15s / 读 30s / 写 15s（超时统一映射 NETWORK）
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 15),
  ));
  return ServerApiClient(
    dio,
    baseUrl: AppConfig.serverBaseUrl,
    tokenProvider: () async {
      final settings = await ref.read(settingsRepositoryProvider).getSettings();
      return settings?.serverToken;
    },
  );
});

/// 服务端文章 API（今日已审核文章拉取；与登录共用同一 ServerApiClient）。
final articleApiProvider = Provider<ArticleApi>((ref) {
  return ArticleApi(ref.watch(serverApiClientProvider));
});

/// 设备标识（shared_preferences 持久化，首次生成后固定；登录/登出请求体）。
final deviceIdProvider = Provider<DeviceIdProvider>((ref) => DeviceIdProvider());

/// 本机号码读取（MethodChannel `contexta/native`；不可用返回 null 走手动输入）。
final nativePhoneReaderProvider =
    Provider<NativePhoneReader>((ref) => NativePhoneReader());

/// 认证状态机（登录/登出/401 恢复）。构造时接线 ServerApiClient 的
/// authCallback → handleServerFailure（清 token + evicted/banned/loggedOut）。
final authServiceProvider = StateNotifierProvider<AuthService, AuthState>((ref) {
  final service = AuthService(
    api: ref.watch(serverApiClientProvider),
    settings: ref.watch(settingsRepositoryProvider),
    deviceId: () => ref.read(deviceIdProvider).getDeviceId(),
    readPhone: () => ref.read(nativePhoneReaderProvider).readLine1Number(),
  );
  ref.read(serverApiClientProvider).setAuthCallback(service.handleServerFailure);
  return service;
});

/// 应用路由（登录守卫：服务端配置且未登录 → /login 带来源回跳；
/// 登录成功（状态变更）经 refreshListenable 自动回跳）。
final routerProvider = Provider<GoRouter>((ref) {
  final authService = ref.read(serverConfiguredProvider)
      ? ref.read(authServiceProvider.notifier)
      : null;
  return buildRouter(authService: authService);
});

/// 时间注入：ISO 偏移日期时间（与 Kotlin TimeProvider.nowDateTimeString 对齐）。
final nowIsoProvider = Provider<String Function()>((ref) => () => isoOffsetDateTime(DateTime.now()));

/// 日期注入：yyyy-MM-dd（与 Kotlin Converter.currentDateString 对齐）。
final todayProvider = Provider<String Function()>((ref) => () => isoLocalDate(DateTime.now()));

/// 时间抽象（Kotlin TimeProvider 对应物）。
final timeProvider = Provider<TimeProvider>(
  (ref) => _ProdTimeProvider(),
);

/// 应用信息（版本号/型号；Kotlin AppInfoProvider 对应物）。
final appInfoProvider = Provider<AppInfoProvider>(
  (ref) => _ProdAppInfoProvider(),
);

/// 后台生成调度器（Kotlin BackgroundWorkScheduler 对应物；
/// 对照 Kotlin GenerationScheduler：workmanager 网关 + KEEP 策略 +
/// 指数退避 + expedited 前台通知）。
final backgroundWorkSchedulerProvider = Provider<BackgroundWorkScheduler>((ref) {
  return GenerationScheduler(gateway: RealWorkmanagerGateway());
});

/// DeepSeek HTTP 客户端（dio；对照 Kotlin NetworkModule：连接 30s、
/// 读超时 = LLM 超时 + 60s 宽限，协程级超时确定性先触发）。
final deepSeekApiProvider = Provider<DeepSeekApi>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      // 读超时 = 协程级 LLM 超时 + 60s 宽限（Kotlin READ_TIMEOUT_GRACE_MS）：
      // 若 <= 协程超时，dio 会先超时触发重试风暴；若相等则竞态；
      // 大于时 LlmCaller 的预算超时确定性胜出
      receiveTimeout: Duration(milliseconds: AppConfig.llmTimeoutMs + 60000),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
  return DioDeepSeekApi(dio);
});

/// 统一 LLM 客户端（重试 + 三分类 + 总预算超时）。
final llmClientProvider = Provider<LlmClient>((ref) {
  return LlmCaller(ref.watch(deepSeekApiProvider));
});

/// TTS 缓存管理器（段落级 WAV 缓存 + FIFO 淘汰 50MB）。
final ttsCacheManagerProvider = Provider<TtsCacheManager>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return TtsCacheManager(db: db);
});

/// TTS 引擎（KittenTTS 默认，初始化失败自动回退系统 TTS；
/// 对照 Kotlin TtsEngineImpl 的三重引擎链）。
final ttsEngineProvider = FutureProvider<TtsEngine>((ref) {
  return TtsEngineFactory(
    kittenAssetBasePath: 'assets/kittentts_models',
    cache: ref.watch(ttsCacheManagerProvider),
  ).create();
});

/// 词库仓储（LRU(50) + Semaphore(3)，单例：缓存与并发限制跨调用共享）。
final wordRepositoryProvider = Provider<WordRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return WordRepositoryImpl(
    WordDao(db),
    WordSenseDao(db),
    ExampleSentenceDao(db),
    VocabularyEntryDao(db),
  );
});

final articleRepositoryProvider = Provider<ArticleRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return ArticleRepositoryImpl(
    db,
    ArticleBatchDao(db),
    ArticleDao(db),
    ArticleParagraphDao(db),
    GenerationPipelineStatusDao(db),
    GenerationErrorLogDao(db),
    DailyLearningDao(db),
    ref.watch(nowIsoProvider),
    ref.watch(todayProvider),
  );
});

final vocabularyRepositoryProvider = Provider<VocabularyRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return VocabularyRepositoryImpl(
    VocabularyEntryDao(db),
    ref.watch(wordRepositoryProvider),
    ref.watch(nowIsoProvider),
  );
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return SettingsRepositoryImpl(UserSettingsDao(db));
});

/// 当前朗读音色（所有 TTS 消费方共用；无设置行时默认 Bella）。
final currentTtsVoiceProvider = FutureProvider<TtsVoice>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider).getSettings();
  return settings?.ttsVoice ?? TtsVoice.bella;
});

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return StatsRepositoryImpl(
    DailyLearningLogDao(db),
    LearningStatsSummaryDao(db),
    ref.watch(vocabularyRepositoryProvider),
    ref.watch(todayProvider),
  );
});

// ─── Use cases ─────────────────────────────────────────────────────────

final triggerNextBatchUseCaseProvider = Provider<TriggerNextBatchUseCase>((ref) {
  return TriggerNextBatchUseCase(
    articleRepository: ref.watch(articleRepositoryProvider),
    generationScheduler: ref.watch(backgroundWorkSchedulerProvider),
    timeProvider: ref.watch(timeProvider),
  );
});

final activateSeedBatchUseCaseProvider = Provider<ActivateSeedBatchUseCase>((ref) {
  return ActivateSeedBatchUseCase(
    articleRepository: ref.watch(articleRepositoryProvider),
    timeProvider: ref.watch(timeProvider),
  );
});

final createInitialBatchUseCaseProvider = Provider<CreateInitialBatchUseCase>((ref) {
  return CreateInitialBatchUseCase(
    articleRepository: ref.watch(articleRepositoryProvider),
    triggerNextBatch: ref.watch(triggerNextBatchUseCaseProvider),
    timeProvider: ref.watch(timeProvider),
  );
});

/// 每日文章同步用例（fetchToday 经 ArticleApi；T6 编排在登录后触发）。
/// 直连 DAO（简报裁定）：不经过 ArticleRepository 大接口。
final syncArticlesUseCaseProvider = Provider<SyncArticlesUseCase>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return SyncArticlesUseCase(
    batchDao: ArticleBatchDao(db),
    articleDao: ArticleDao(db),
    paragraphDao: ArticleParagraphDao(db),
    fetchToday: () => ref.read(articleApiProvider).fetchTodayArticles(),
    timeProvider: ref.watch(timeProvider),
  );
});

final generateArticlesUseCaseProvider = Provider<GenerateArticlesUseCase>((ref) {
  return GenerateArticlesUseCase(
    articleRepository: ref.watch(articleRepositoryProvider),
    llmClient: ref.watch(llmClientProvider),
    timeProvider: ref.watch(timeProvider),
    appInfo: ref.watch(appInfoProvider),
    alertSender: ref.watch(developerAlertSenderProvider),
  );
});

final getHomeArticlesUseCaseProvider = Provider<GetHomeArticlesUseCase>((ref) {
  return GetHomeArticlesUseCase();
});

final resendPendingAlertsUseCaseProvider = Provider<ResendPendingAlertsUseCase>((ref) {
  return ResendPendingAlertsUseCase(
    articleRepository: ref.watch(articleRepositoryProvider),
    alertSender: ref.watch(developerAlertSenderProvider),
    timeProvider: ref.watch(timeProvider),
    appInfo: ref.watch(appInfoProvider),
  );
});

final startupOrchestrationUseCaseProvider = Provider<StartupOrchestrationUseCase>((ref) {
  return StartupOrchestrationUseCase(
    articleRepository: ref.watch(articleRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    timeProvider: ref.watch(timeProvider),
    triggerNextBatch: ref.watch(triggerNextBatchUseCaseProvider),
    generationScheduler: ref.watch(backgroundWorkSchedulerProvider),
    resendPendingAlerts: ref.watch(resendPendingAlertsUseCaseProvider),
  );
});

final addWordUseCaseProvider = Provider<AddWordUseCase>((ref) {
  return AddWordUseCase(
    wordRepository: ref.watch(wordRepositoryProvider),
    vocabularyRepository: ref.watch(vocabularyRepositoryProvider),
    statsRepository: ref.watch(statsRepositoryProvider),
    llmClient: ref.watch(llmClientProvider),
  );
});

/// 开发告警发送器（飞书 webhook；对照 Kotlin DomainModule 绑定
/// FeishuAlertSender → DeveloperAlertSender）。
final developerAlertSenderProvider = Provider<DeveloperAlertSender>((ref) {
  return FeishuAlertSender(
    timeProvider: ref.watch(timeProvider),
    webhookUrl: AppConfig.feishuWebhookUrl,
    signSecret: AppConfig.feishuSignSecret,
  );
});

// ─── 生产实现（AppInfoProvider / TimeProvider） ────────────────────────

class _ProdTimeProvider implements TimeProvider {
  @override
  int nowMillis() => DateTime.now().millisecondsSinceEpoch;

  @override
  String nowDateTimeString() => isoOffsetDateTime(DateTime.now());

  @override
  String todayDateString() => isoLocalDate(DateTime.now());

  @override
  String nextDateString() =>
      isoLocalDate(DateTime.now().add(const Duration(days: 1)));
}

class _ProdAppInfoProvider implements AppInfoProvider {
  @override
  int get versionCode => 1;

  @override
  String get versionName => '1.0';

  @override
  String get deviceModel => 'unknown';
}
