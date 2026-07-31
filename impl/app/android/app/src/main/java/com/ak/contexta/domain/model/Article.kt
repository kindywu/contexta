package com.ak.contexta.domain.model

data class Article(
    val id: Long,
    val batchId: Long,
    val orderIndex: Int,
    val contentCategory: String,
    val title: String?,
    val status: ArticleStatus,
    val generationStartedAt: String?,
    val generationCompletedAt: String?,
    val retryCount: Int,
    val accumulatedReadSeconds: Int,
    val readCompletedAt: String?,
    val lastRetryAt: String?,
    val maxRetries: Int = 3,
    val nextRetryAt: String? = null,
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
