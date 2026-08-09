import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../domain/background_work_scheduler.dart';

/// 一次性任务的调度参数（对照 Kotlin GenerationScheduler 的
/// OneTimeWorkRequestBuilder 配置：KEEP 策略、指数退避 30s、expedited +
/// 前台通知、tag）。
class GenerationTaskSpec {
  const GenerationTaskSpec({
    required this.uniqueName,
    required this.taskName,
    required this.inputData,
    required this.tag,
    this.initialDelay,
    this.constraints,
    this.existingWorkPolicy = ExistingWorkPolicy.keep,
    this.backoffPolicy = BackoffPolicy.exponential,
    this.backoffPolicyDelay = const Duration(seconds: 30),
    this.outOfQuotaPolicy = OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
    this.foregroundServiceConfig,
    this.expedited = false,
  });

  final String uniqueName;
  final String taskName;
  final Map<String, dynamic> inputData;
  final String? tag;
  final Duration? initialDelay;
  final Constraints? constraints;
  final ExistingWorkPolicy existingWorkPolicy;
  final BackoffPolicy backoffPolicy;
  final Duration backoffPolicyDelay;
  final OutOfQuotaPolicy outOfQuotaPolicy;
  final ForegroundServiceConfig? foregroundServiceConfig;
  final bool expedited;
}

/// WorkManager 平台网关（[Workmanager] 单例 + 私有构造函数，无法继承/注入，
/// 故定义网关接口；生产实现委托给 [Workmanager]，测试注入 fake）。
abstract interface class WorkmanagerGateway {
  Future<void> registerOneOffTask(GenerationTaskSpec spec);

  Future<void> cancelByUniqueName(String uniqueName);

  Future<void> cancelByTag(String tag);

  Future<void> cancelAll();
}

/// 生产网关：直接委托 [Workmanager] 单例。
class RealWorkmanagerGateway implements WorkmanagerGateway {
  @override
  Future<void> registerOneOffTask(GenerationTaskSpec spec) {
    return Workmanager().registerOneOffTask(
      spec.uniqueName,
      spec.taskName,
      inputData: spec.inputData,
      initialDelay: spec.initialDelay,
      constraints: spec.constraints,
      existingWorkPolicy: spec.existingWorkPolicy,
      backoffPolicy: spec.backoffPolicy,
      backoffPolicyDelay: spec.backoffPolicyDelay,
      tag: spec.tag,
      outOfQuotaPolicy: spec.outOfQuotaPolicy,
      foregroundServiceConfig: spec.foregroundServiceConfig,
      expedited: spec.expedited,
    );
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) =>
      Workmanager().cancelByUniqueName(uniqueName);

  @override
  Future<void> cancelByTag(String tag) => Workmanager().cancelByTag(tag);

  @override
  Future<void> cancelAll() => Workmanager().cancelAll();
}

/// 文章生成任务调度器（对照 Kotlin GenerationScheduler.kt）。
///
/// - uniqueWorkName = "article_generation_batch_$batchId"，KEEP 策略：
///   同批次已有排队/运行中的任务时丢弃新请求（防止重复生成）
/// - tag = "batch_$batchId"；cancelAllGeneration 对照 Kotlin 用
///   "article_generation" tag（Kotlin 请求未打该 tag，功能上等价于
///   cancelAllWork —— 保持行为对齐）
/// - expedited 以前台服务运行（避免 MIUI 节流），配额耗尽降级普通 work
class GenerationScheduler implements BackgroundWorkScheduler {
  GenerationScheduler({required this._gateway});

  GenerationScheduler.unittest(this._gateway);

  static const String uniqueWorkPrefix = 'article_generation_batch_';
  static const String cancelAllTag = 'article_generation';
  static const String taskName = 'articleGeneration';

  /// 前台服务通知（对照 Kotlin ArticleGenerationWorker.getForegroundInfo）：
  /// channel article_generation/文章生成（IMPORTANCE_LOW，插件自动创建），
  /// 标题 "Contexta 正在生成文章"，正文 "批次 #N 生成中…"（batchId 缺失
  /// 时 "生成中…"），notificationId 1001。
  ///
  /// 前台服务类型用 shortService（Android 14+）：Kotlin expedited work 由
  /// WorkManager 以 shortService FGS 运行，这里显式声明保持一致；且
  /// dataSync 需 Play Console 特殊类型申报 + gradle 属性 opt-in，shortService
  /// 零额外配置。插件自动声明 FOREGROUND_SERVICE_SHORT_SERVICE 权限。
  static ForegroundServiceConfig foregroundConfig(int batchId) {
    return ForegroundServiceConfig(
      notificationTitle: 'Contexta 正在生成文章',
      notificationText: batchId > 0 ? '批次 #$batchId 生成中…' : '生成中…',
      notificationChannelId: 'article_generation',
      notificationChannelName: '文章生成',
      notificationId: 1001,
      foregroundServiceType: ForegroundServiceType.shortService,
    );
  }

  final WorkmanagerGateway _gateway;

  @override
  Future<bool> scheduleBatchGeneration(int batchId,
      {int appVersionCode = 0}) async {
    final uniqueName = '$uniqueWorkPrefix$batchId';
    debugPrint('[GenerationScheduler] scheduleBatchGeneration batch=$batchId uniqueName=$uniqueName');
    // 不用 expedited：workmanager_android 0.10.6 在 expedited=true 时硬检查
    // FOREGROUND_SERVICE_SHORT_SERVICE 权限（checkPermission），而 Android 15+
    // 系统已移除该权限（HyperOS 真机 pm grant 报 Unknown permission），
    // checkPermission 恒 DENIED → 抛 PlatformException → 调度失败 →
    // worker 从未入队 → 批次永远卡 PENDING（原 Android 版同为 expedited
    // 但用 WorkManager 原生 API 无此检查；Flutter 插件层有）。
    await _gateway.registerOneOffTask(
      GenerationTaskSpec(
        uniqueName: uniqueName,
        taskName: taskName,
        inputData: {
          'batchId': batchId,
          'appVersionCode': appVersionCode,
        },
        tag: 'batch_$batchId',
        // expedited: true 曾导致调度崩溃（见上）；改为普通任务
        expedited: false,
        // 前台服务：worker 运行时提升为前台服务（通知 + 进程优先级提升），
        // 规避国产 ROM（HyperOS/MIUI 等）对后台进程的网络封禁——
        // 后台 worker 的 Dio 请求会被系统断网（DioException [unknown]，
        // 日志见 2026-08-09），前台服务视为用户可见，网络豁免。
        // 任务结束自动停止，无需手动管理。
        foregroundServiceConfig: foregroundConfig(batchId),
      ),
    );
    debugPrint('[GenerationScheduler] registered batch=$batchId');
    return true;
  }

  @override
  Future<void> cancelBatchGeneration(int batchId) =>
      _gateway.cancelByUniqueName('$uniqueWorkPrefix$batchId');

  @override
  Future<void> cancelAllGeneration() => _gateway.cancelByTag(cancelAllTag);
}
