package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.repository.ArticleRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 查找并激活匹配的种子批次（首次安装时由 [seedDatabase] 写入的 EXPIRED 批次）。
 *
 * 在 onboarding 完成后调用，将种子批次提升为 CURRENT 并解锁，
 * 让用户立即可看到初始文章，同时触发 NEXT 批次的后台生成。
 */
@Singleton
class ActivateSeedBatchUseCase @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val triggerNextBatch: TriggerNextBatchUseCase
) {
    /**
     * 激活种子批次。
     * @param difficulty 用户选择的难度（LOW / MEDIUM / HIGH）
     * @param dailyCount 用户选择的每日篇数
     * @return true 找到并激活了种子批次，false 无匹配种子
     */
    suspend operator fun invoke(difficulty: String, dailyCount: Int): Boolean {
        val expired = articleRepository.getExpiredBatches()
        val seed = expired.firstOrNull { batch ->
            batch.difficultyLevelSnapshot == difficulty &&
            articleRepository.isBatchComplete(batch.id)
        } ?: return false

        articleRepository.reactivateBatch(seed.id, dailyCount)
        articleRepository.promoteNextToCurrent(seed.id)
        triggerNextBatch(difficulty, dailyCount)
        return true
    }
}
