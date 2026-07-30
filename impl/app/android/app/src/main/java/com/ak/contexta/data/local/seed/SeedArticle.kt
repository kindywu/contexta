package com.ak.contexta.data.local.seed

import kotlinx.serialization.Serializable

@Serializable
data class SeedData(
    val version: Int,
    val seedArticles: List<SeedArticle>
)

@Serializable
data class SeedArticle(
    val difficultyLevel: String,
    val contentCategory: String,
    val orderIndex: Int,
    val title: String,
    val paragraphs: List<SeedParagraph>
)

@Serializable
data class SeedParagraph(
    val orderIndex: Int,
    val englishText: String,
    val chineseTranslation: String
)
