package com.ak.contexta.domain

/**
 * 后台任务调度接口，由 worker 层实现。
 * Domain 层通过此接口触发批量生成任务，不直接依赖 WorkManager。
 */
interface BackgroundWorkScheduler {
    /**
     * 为指定 batch 调度文章生成 Worker。
     * @return 是否成功入队
     */
    fun scheduleBatchGeneration(batchId: Long, appVersionCode: Int = 0): Boolean

    /** 取消指定 batch 的待处理生成任务 */
    fun cancelBatchGeneration(batchId: Long)

    /** 取消所有文章生成任务 */
    fun cancelAllGeneration()
}
