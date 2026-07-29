package com.ak.contexta.domain.model

data class ArticleBatch(
    val id: Long,
    val batchType: BatchType,
    val status: BatchStatus,
    val difficultyLevelSnapshot: String,
    val dailyCountSnapshot: Int,
    val generatedOn: String?,
    val unlockedOn: String?,
    val lastUpdatedAt: Long,
    val articles: List<Article> = emptyList()
)

enum class BatchType(val value: String) {
    CURRENT("CURRENT"),
    NEXT("NEXT");

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
    INVALIDATED("INVALIDATED"),
    BLOCKED("BLOCKED");

    companion object {
        fun from(value: String): BatchStatus =
            entries.firstOrNull { it.value == value } ?: PENDING
    }
}
