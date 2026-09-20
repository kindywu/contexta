import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/navigation/app_router.dart';
import '../core/platform/device_form_factor.dart';
import '../core/time/iso8601.dart';
import '../data/audio/asset_phoneme_audio.dart';
import '../data/auth/auth_service.dart';
import '../data/auth/device_id_provider.dart';
import '../data/auth/device_label_reader.dart';
import '../data/auth/native_phone_reader.dart';
import '../data/local/database_open.dart';
import '../data/local/daos/article_daos.dart';
import '../data/local/daos/settings_daos.dart';
import '../data/local/daos/word_daos.dart';
import '../data/remote/article_api.dart';
import '../data/remote/llm_api.dart';
import '../data/remote/server_api_client.dart';
import '../data/remote/server_trust.dart';
import '../data/sync/sync_articles_usecase.dart';
import '../data/repository/article_repository_impl.dart';
import '../data/repository/settings_repository_impl.dart';
import '../data/repository/stats_repository_impl.dart';
import '../data/repository/vocabulary_repository_impl.dart';
import '../data/repository/word_repository_impl.dart';
import '../data/tts/tts_cache_manager.dart';
import '../data/tts/tts_engine_factory.dart';
import '../domain/repository/article_repository.dart';
import '../domain/audio/phoneme_audio.dart';
import '../domain/repository/settings_repository.dart';
import '../domain/repository/stats_repository.dart';
import '../domain/repository/vocabulary_repository.dart';
import '../domain/model/tts_voice.dart';
import '../domain/repository/word_repository.dart';
import '../domain/time/prod_time_provider.dart';
import '../domain/time/time_provider.dart';
import '../domain/tts/tts_engine.dart';
import '../domain/usecase/activate_seed_batch_usecase.dart';
import '../domain/usecase/add_word_usecase.dart';
import '../domain/usecase/get_home_articles_usecase.dart';
import '../domain/usecase/startup_orchestration_usecase.dart';
import '../data/local/database.dart';

/// 数据库（生产路径：打开时 onCreate 建表 + 种子写入）。
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await buildAppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 服务端是否已配置（SERVER_BASE_URL 非空）。
/// 空 → App 全本地模式：登录页显示配置提示，路由不做登录拦截。测试可 override。
final serverConfiguredProvider = Provider<bool>(
  (ref) => AppConfig.serverBaseUrl.isNotEmpty,
);

/// 内嵌自签名服务端证书与 TLS 装配见 [server_trust.dart]（证书钉扎；2026-09-19 起）。

/// 服务端 API 客户端（认证拦截每次请求从 user_settings 读 token；
/// 登录/登出/同步共用同一实例——T2 遗留：token 变化自动重置 401 去重）。
final serverApiClientProvider = Provider<ServerApiClient>((ref) {
  final dio = Dio(
    BaseOptions(
      // 登录 / 同步接口较短：连接 15s / 读 30s / 写 15s（超时统一映射 NETWORK）
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
    ),
  );
  // TLS：证书钉扎（内嵌自签名证书）；证书未加载 → 不改写适配器（默认信任库）。
  final trustAdapter = buildServerTrustAdapter();
  if (trustAdapter != null) {
    dio.httpClientAdapter = trustAdapter;
  }
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
final deviceIdProvider = Provider<DeviceIdProvider>(
  (ref) => DeviceIdProvider(),
);

/// 本机号码读取（MethodChannel `contexta/native`；不可用返回 null 走手动输入）。
final nativePhoneReaderProvider = Provider<NativePhoneReader>(
  (ref) => NativePhoneReader(),
);

/// 设备机型名读取（登录上报 device_name；通道不可用 → null）。
final deviceLabelReaderProvider = Provider<DeviceLabelReader>(
  (ref) => DeviceLabelReader(),
);

/// 认证状态机（登录/登出/401 恢复）。构造时接线 ServerApiClient 的
/// authCallback → handleServerFailure（清 token + evicted/banned/loggedOut）。
final authServiceProvider = StateNotifierProvider<AuthService, AuthState>((
  ref,
) {
  final service = AuthService(
    api: ref.watch(serverApiClientProvider),
    settings: ref.watch(settingsRepositoryProvider),
    deviceId: () => ref.read(deviceIdProvider).getDeviceId(),
    readPhone: () => ref.read(nativePhoneReaderProvider).readLine1Number(),
    readDeviceLabel: () => ref.read(deviceLabelReaderProvider).readDeviceLabel(),
  );
  ref
      .read(serverApiClientProvider)
      .setAuthCallback(service.handleServerFailure);
  return service;
});

/// 应用路由（启动落点：已引导 → 直接落首页不再渲染向导页；
/// 登录守卫：服务端配置且未登录 → /login 带来源回跳；
/// 登录成功（状态变更）经 refreshListenable 自动回跳）。
final routerProvider = Provider<GoRouter>((ref) {
  final authService = ref.read(serverConfiguredProvider)
      ? ref.read(authServiceProvider.notifier)
      : null;
  // DB 就绪由 MainApp 门禁保证（routerProvider 只在 databaseProvider 的
  // data 分支被 watch），此处 requireValue 安全。
  final settingsRepository = ref.read(settingsRepositoryProvider);
  return buildRouter(
    // 启动时判定一次的设备形态（main() 覆写注入）——界面树分派的唯一依据
    formFactor: ref.read(formFactorProvider),
    authService: authService,
    isOnboarded: settingsRepository.isOnboarded,
  );
});

/// 时间注入：ISO 偏移日期时间（与 Kotlin TimeProvider.nowDateTimeString 对齐）。
final nowIsoProvider = Provider<String Function()>(
  (ref) =>
      () => isoOffsetDateTime(DateTime.now()),
);

/// 日期注入：yyyy-MM-dd（与 Kotlin Converter.currentDateString 对齐）。
final todayProvider = Provider<String Function()>(
  (ref) =>
      () => isoLocalDate(DateTime.now()),
);

/// 时间抽象（Kotlin TimeProvider 对应物；生产实现提为公共
/// ProdTimeProvider——后台 isolate 的 syncCallbackDispatcher 共用，见
/// domain/time/prod_time_provider.dart）。
final timeProvider = Provider<TimeProvider>((ref) => ProdTimeProvider());

/// 服务端 LLM 网关 API（查词远程化；与登录/同步共用同一 ServerApiClient）。
final llmApiProvider = Provider<LlmApi>((ref) {
  return LlmApi(ref.watch(serverApiClientProvider));
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

/// 音标录音库（48 个音标，随包分发；音标发音不走 TTS）。
final phonemeAudioProvider = Provider<PhonemeAudio>((ref) {
  return AssetPhonemeAudio();
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
    ArticleBatchDao(db),
    ArticleDao(db),
    ArticleParagraphDao(db),
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

/// 当前朗读音色（**非文章**入口共用：参考页例句 / 词汇页单词）。
///
/// 设置选固定音色 → 返回该音色；选「随机」→ 随机挑一个（FutureProvider 结果
/// 会缓存，故同一次会话内稳定，不会每次朗读换嗓子）。文章朗读不走这里——
/// 它按篇文章随机分配并持久化，见 ReadingController._resolveVoice。
final currentTtsVoiceProvider = FutureProvider<TtsVoice>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider).getSettings();
  final setting = settings?.ttsVoice ?? const TtsVoiceSetting.random();
  return setting.voice ?? TtsVoice.pickRandom(ref.watch(ttsVoiceRandomProvider));
});

/// 音色随机源（测试可 override 固定种子断言具体音色）。
final ttsVoiceRandomProvider = Provider<Random>((ref) => Random());

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

final activateSeedBatchUseCaseProvider = Provider<ActivateSeedBatchUseCase>((
  ref,
) {
  return ActivateSeedBatchUseCase(
    articleRepository: ref.watch(articleRepositoryProvider),
    timeProvider: ref.watch(timeProvider),
  );
});

/// 每日文章同步用例（fetchDelivery 经 ArticleApi；difficulty/count 取自
/// user_settings——启动时按当前难度设置投放）。直连 DAO（简报裁定）。
final syncArticlesUseCaseProvider = Provider<SyncArticlesUseCase>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return SyncArticlesUseCase(
    db: db,
    batchDao: ArticleBatchDao(db),
    articleDao: ArticleDao(db),
    paragraphDao: ArticleParagraphDao(db),
    fetchDelivery: () async {
      final settings = await ref.read(settingsRepositoryProvider).getSettings();
      return ref.read(articleApiProvider).fetchDelivery(
        difficulty: settings?.difficultyLevel ?? 'MEDIUM',
        count: settings?.dailyArticleCount ?? 3,
      );
    },
    timeProvider: ref.watch(timeProvider),
  );
});

final getHomeArticlesUseCaseProvider = Provider<GetHomeArticlesUseCase>((ref) {
  return GetHomeArticlesUseCase();
});

/// 启动编排（服务端同步模型，2026-08-13 计划 B Task 5）：
/// onboarding → 登录检查 → SyncArticlesUseCase 每日同步（失败降级不阻塞首页）
/// → 今天无 daily_learning 时按用户难度分配今天批次。
final startupOrchestrationUseCaseProvider =
    Provider<StartupOrchestrationUseCase>((ref) {
      return StartupOrchestrationUseCase(
        articleRepository: ref.watch(articleRepositoryProvider),
        settingsRepository: ref.watch(settingsRepositoryProvider),
        timeProvider: ref.watch(timeProvider),
        syncArticles: ref.watch(syncArticlesUseCaseProvider),
      );
    });

final addWordUseCaseProvider = Provider<AddWordUseCase>((ref) {
  return AddWordUseCase(
    wordRepository: ref.watch(wordRepositoryProvider),
    vocabularyRepository: ref.watch(vocabularyRepositoryProvider),
    statsRepository: ref.watch(statsRepositoryProvider),
    llmApi: ref.watch(llmApiProvider),
  );
});
