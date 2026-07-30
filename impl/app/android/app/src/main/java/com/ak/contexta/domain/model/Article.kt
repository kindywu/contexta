package com.ak.contexta.domain.model

data class Article(
    val id: Long,
    val batchId: Long,
    val orderIndex: Int,
    val contentCategory: String,
    val title: String?,
    val status: ArticleStatus,
    val generationStartedAt: Long?,
    val generationCompletedAt: Long?,
    val retryCount: Int,
    val accumulatedReadSeconds: Int,
    val readCompletedAt: Long?,
    val lastRetryAt: Long?,
    val errorCode: String? = null,
    val errorMessage: String? = null,
    val errorHelp: String? = null,
    val maxRetries: Int = 3,
    val nextRetryAt: Long? = null,
    val paragraphs: List<ArticleParagraph> = emptyList()
)

enum class ArticleStatus(val value: String) {
    PENDING("PENDING"),
    GENERATING("GENERATING"),
    SUCCESS("SUCCESS"),
    TIMEOUT("TIMEOUT"),
    FAILED("FAILED"),
    FATAL("FATAL");

    companion object {
        fun from(value: String): ArticleStatus =
            entries.firstOrNull { it.value == value } ?: PENDING
    }
}

data class ArticleParagraph(
    val orderIndex: Int,
    val englishText: String,
    val chineseTranslation: String
)
