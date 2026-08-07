/// 后台任务调度接口（对照 Kotlin BackgroundWorkScheduler.kt），
/// 由 worker 层实现；Domain 层通过此接口触发批量生成任务，不直接依赖 WorkManager。
abstract interface class BackgroundWorkScheduler {
  /// 为指定 batch 调度文章生成 Worker。返回是否成功入队。
  Future<bool> scheduleBatchGeneration(int batchId, {int appVersionCode = 0});

  /// 取消指定 batch 的待处理生成任务。
  Future<void> cancelBatchGeneration(int batchId);

  /// 取消所有文章生成任务。
  Future<void> cancelAllGeneration();
}
