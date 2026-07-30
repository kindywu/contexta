package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.repository.ArticleRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 查找并激活匹配的种子批次（首次安装时由 [seedDatabase] 写入的 READY 批次）。
 *
 * 在 onboarding 完成后调用，将种子批次分配给今天的 daily_learning，
 * 让用户立即可看到初始文章，同时触发后续批次的后台生成。
 *
 * **在新系统下，[StartupOrchestrationUseCase] 已经能自动完成此任务。**
 * 此 Use Case 作为 onboaring 完成后的立即激活，确保用户在跳转到首页前
 * 批次已被分配，避免首页闪烁。
 */
@Singleton
class ActivateSeedBatchUseCase @Inject constructor(
    private val articleRepository: ArticleRepository
) {
    /**
     * 激活种子批次：查找匹配的 READY 批次并分配给今天。
     * @param difficulty 用户选择的难度
     * @param dailyCount 用户选择的每日篇数
     * @return true 找到并激活了种子批次，false 无匹配种子
     */
    suspend operator fun invoke(difficulty: String, dailyCount: Int): Boolean {
        val batch = articleRepository.findNextReadyBatch(
            difficulty = difficulty,
            afterDate = null
        ) ?: return false

        // 即使 assign 失败（今天已有记录），也算找到种子了
        articleRepository.assignBatchForToday(
            batchId = batch.id,
            refBatchDate = batch.generatedOn ?: java.time.LocalDate.now().toString(),
            dailyCount = dailyCount
        )
        return true
    }
}
