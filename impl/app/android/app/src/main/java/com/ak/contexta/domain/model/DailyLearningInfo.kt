package com.ak.contexta.domain.model

/**
 * 每日学习记录（含关联的批次信息）。
 * 用于首页展示用户的学习历史。
 */
data class DailyLearningInfo(
    val learningDate: String,
    val dailyCountSnapshot: Int,
    val batch: ArticleBatch
)
