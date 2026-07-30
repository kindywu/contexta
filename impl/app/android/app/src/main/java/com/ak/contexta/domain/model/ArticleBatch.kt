package com.ak.contexta.domain.model

data class ArticleBatch(
    val id: Long,
    val batchType: BatchType,
    val status: BatchStatus,
    val difficultyLevelSnapshot: String,
    /**
     * 首页展示文章数量上限（非生成数量）。
     * 生成数量固定为 MAX_ARTICLES_PER_BATCH=5（见 TriggerNextBatchUseCase）。
     * 此值为批次创建时用户的 daily_article_count 快照，修改设置不影响已有批次。
     */
    val dailyCountSnapshot: Int,
    val generatedOn: String?,
    val unlockedOn: String?,
    val lastUpdatedAt: Long,
    val errorCode: String? = null,
    val errorMessage: String? = null,
    val blockedReason: String? = null,
    val blockedAt: Long? = null,
    val articles: List<Article> = emptyList()
)

enum class BatchType(val value: String) {
    CURRENT("CURRENT"),
    NEXT("NEXT"),
    EXPIRED("EXPIRED");

    companion object {
        fun from(value: String): BatchType =
            entries.firstOrNull { it.value == value } ?: CURRENT
    }
}

enum class BatchStatus(val value: String) {
    PENDING("PENDING"),
    GENERATING("GENERATING"),
    READY("READY"),
    CURRENT("CURRENT"),
    EXPIRED("EXPIRED"),
    BLOCKED("BLOCKED");

    companion object {
        fun from(value: String): BatchStatus =
            entries.firstOrNull { it.value == value } ?: PENDING
    }
}
