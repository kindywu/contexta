package com.ak.contexta.domain.model

data class ArticleBatch(
    val id: Long,
    val status: BatchStatus,
    val difficultyLevelSnapshot: String,
    val generatedOn: String?,
    val lastUpdatedAt: Long,
    val errorCode: String? = null,
    val errorMessage: String? = null,
    val blockedReason: String? = null,
    val blockedAt: Long? = null,
    val articles: List<Article> = emptyList()
)

enum class BatchStatus(val value: String) {
    PENDING("PENDING"),
    GENERATING("GENERATING"),
    READY("READY"),
    CURRENT("CURRENT"),
    BLOCKED("BLOCKED");

    companion object {
        fun from(value: String): BatchStatus =
            entries.firstOrNull { it.value == value } ?: PENDING
    }
}
