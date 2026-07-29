package com.ak.contexta.data.local.seed

import kotlinx.serialization.Serializable

@Serializable
data class SeedDataDto(
    val version: Int,
    val seedArticles: List<SeedArticleDto>
)

@Serializable
data class SeedArticleDto(
    val difficultyLevel: String,
    val contentCategory: String,
    val orderIndex: Int,
    val title: String,
    val paragraphs: List<SeedParagraphDto>
)

@Serializable
data class SeedParagraphDto(
    val orderIndex: Int,
    val englishText: String,
    val chineseTranslation: String
)
