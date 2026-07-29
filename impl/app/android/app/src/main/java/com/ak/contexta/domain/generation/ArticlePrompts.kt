package com.ak.contexta.domain.generation

import com.ak.contexta.domain.model.ArticleParagraph

/**
 * Maps a content category to its difficulty level.
 */
fun categoryToDifficulty(category: String): String = when (category) {
    "DAILY_CONVERSATION", "SCENE_DESCRIPTION", "SIMPLE_STORY" -> "LOW"
    "NEWS", "EXPOSITORY", "ARGUMENTATIVE", "PERSONAL_ESSAY" -> "MEDIUM"
    "ACADEMIC_EXCERPT", "DEBATE_SPEECH", "LEGAL_DOCUMENT", "ART_CRITICISM", "CLASSIC_NOVEL_EXCERPT" -> "HIGH"
    else -> "MEDIUM"
}

/**
 * System prompt for article generation via LLM.
 *
 * Loads COMMON + <difficulty> sections from `article_system.txt`.
 * Supports placeholders: {{title}} (kept as-is for LLM to fill).
 *
 * @param difficulty "LOW", "MEDIUM", or "HIGH". If null, returns only the COMMON section.
 */
fun buildArticleSystemPrompt(difficulty: String? = null): String {
    val sections = listOfNotNull("COMMON", difficulty)
    return PromptLoader.loadSection(
        "article_system.txt",
        sections = sections,
        params = mapOf("title" to "The Article Title"),
        fallback = buildString {
            appendLine("You are an English language learning content creator.")
            appendLine("You create articles for Chinese learners at various difficulty levels.")
            appendLine()
            appendLine("Output format:")
            appendLine("<title>The Article Title</title>")
            appendLine("<paragraph>English sentence here.</paragraph>")
            appendLine("<translation>中文翻译。</translation>")
            appendLine("<paragraph>Next sentence.</paragraph>")
            appendLine("<translation>下一句翻译。</translation>")
            appendLine()
            appendLine("Rules:")
            appendLine("- Each paragraph must be 1-3 sentences, not longer")
            appendLine("- Each <paragraph> must be immediately followed by <translation>")
            appendLine("- Title must be 2-8 words")
            appendLine("- Output only the XML — no explanations, no markdown")
        }
    )
}

/**
 * User prompt for article generation, specific to the content category.
 *
 * Uses the USER_PROMPT section from `article_system.txt` as a base,
 * then appends the category-specific guidelines in code (structured logic).
 */
fun buildArticleUserPrompt(category: String, orderIndex: Int): String {
    val basePrompt = PromptLoader.loadSection(
        "article_system.txt",
        sections = listOf("USER_PROMPT"),
        params = mapOf("orderIndex" to orderIndex.toString(), "category" to category),
        fallback = "Create article #$orderIndex in the category: $category"
    )

    val guideline = categoryGuideline(category)
    return if (guideline != null) {
        "$basePrompt\n\nGuidelines for $category:\n$guideline"
    } else {
        basePrompt
    }
}

private fun categoryGuideline(category: String): String? = when (category) {
    "DAILY_CONVERSATION" -> "A natural everyday dialogue or scenario between two people."
    "SCENE_DESCRIPTION" -> "A vivid description of a place, event, or moment."
    "SIMPLE_STORY" -> "A short narrative with a clear beginning and end."
    "NEWS" -> "A brief news-style report on a current or hypothetical event."
    "EXPOSITORY" -> "An explanatory piece that teaches a concept."
    "ARGUMENTATIVE" -> "A short argument for or against a position."
    "PERSONAL_ESSAY" -> "A reflective first-person piece on an experience."
    "ACADEMIC_EXCERPT" -> "A scholarly excerpt suitable for advanced readers."
    "DEBATE_SPEECH" -> "A persuasive speech or debate opening statement."
    "LEGAL_DOCUMENT" -> "A simplified legal clause or contract excerpt."
    "ART_CRITICISM" -> "An analytical piece about an artwork or performance."
    "CLASSIC_NOVEL_EXCERPT" -> "An excerpt in the style of classic English literature."
    else -> null
}

/**
 * Parse LLM response in XML format:
 * <title>...</title>
 * <paragraph>...</paragraph>
 * <translation>...</translation>
 *
 * Returns a pair of (title, list of paragraphs with translations).
 */
fun parseArticleLlmResponse(content: String): Pair<String, List<ArticleParagraph>> {
    val title = Regex("<title>([\\s\\S]*?)</title>").find(content)
        ?.groupValues?.get(1)?.trim() ?: "Untitled"

    val paragraphRegex = Regex("<paragraph>([\\s\\S]*?)</paragraph>")
    val translationRegex = Regex("<translation>([\\s\\S]*?)</translation>")

    val paragraphs = paragraphRegex.findAll(content).map { it.groupValues[1].trim() }.toList()
    val translations = translationRegex.findAll(content).map { it.groupValues[1].trim() }.toList()

    val result = paragraphs.mapIndexed { index, englishText ->
        val translation = translations.getOrElse(index) { "" }
        ArticleParagraph(
            orderIndex = index + 1,
            englishText = englishText,
            chineseTranslation = translation
        )
    }

    return Pair(title, result)
}
