package com.ak.contexta.domain.generation

import com.ak.contexta.domain.model.ExampleSentence
import com.ak.contexta.domain.model.WordDetail
import com.ak.contexta.domain.model.WordSense

/**
 * System prompt for word definition lookup via LLM.
 *
 * Loads the base template from `src/main/resources/prompts/word_lookup_system.txt`.
 * Falls back to a built-in string if the template file is unavailable.
 */
fun buildWordLookupSystemPrompt(): String = PromptLoader.load(
    "word_lookup_system.txt",
    fallback = buildString {
        appendLine("You are an English-Chinese dictionary assistant.")
        appendLine("Given an English word, provide its detailed definition for Chinese learners.")
        appendLine()
        appendLine("Output format:")
        appendLine("<spelling>TheWord</spelling>")
        appendLine("<phonetic>/fəˈnɛtɪk/</phonetic>")
        appendLine("<sense>")
        appendLine("  <partOfSpeech>n.</partOfSpeech>")
        appendLine("  <chineseMeaning>中文释义</chineseMeaning>")
        appendLine("  <englishDefinition>English definition of this sense.</englishDefinition>")
        appendLine("  <example>")
        appendLine("    <en>Example sentence in English.</en>")
        appendLine("    <zh>例句的中文翻译。</zh>")
        appendLine("  </example>")
        appendLine("</sense>")
        appendLine()
        appendLine("Rules:")
        appendLine("- <phonetic> is optional — include if available, omit the tag entirely if unknown")
        appendLine("- Provide 1-3 <sense> blocks; at least 1 is required")
        appendLine("- Each <sense> must have <partOfSpeech>, <chineseMeaning>, <englishDefinition>")
        appendLine("- Each <sense> should have 0-2 <example> blocks; <example> is optional")
        appendLine("- <example> must contain both <en> and <zh>")
        appendLine("- Output only the XML — no explanations, no markdown")
        appendLine("- Escape XML special characters: &amp; → &amp;amp;, < → &amp;lt;, > → &amp;gt;")
    }
)

/**
 * User prompt for word definition lookup.
 */
fun buildWordLookupUserPrompt(word: String): String = buildString {
    appendLine("Look up the word: $word")
    appendLine()
    appendLine("Provide the spelling, phonetic transcription (if known), and all common senses with example sentences.")
}

/**
 * Parse LLM response in XML format for word definitions:
 * <spelling>...</spelling>
 * <phonetic>...</phonetic>
 * <sense>
 *   <partOfSpeech>...</partOfSpeech>
 *   <chineseMeaning>...</chineseMeaning>
 *   <englishDefinition>...</englishDefinition>
 *   <example>
 *     <en>...</en>
 *     <zh>...</zh>
 *   </example>
 * </sense>
 *
 * Returns a [WordDetail] with no DB IDs (wordId = 0, sense/example IDs = 0).
 * Returns null if no valid senses could be parsed.
 */
fun parseWordLlmResponse(content: String): WordDetail? {
    val spelling = Regex("<spelling>([\\s\\S]*?)</spelling>").find(content)
        ?.groupValues?.get(1)?.trim()
        ?: return null // spelling is required

    val phonetic = Regex("<phonetic>([\\s\\S]*?)</phonetic>").find(content)
        ?.groupValues?.get(1)?.trim()

    val senseRegex = Regex(
        "<sense>([\\s\\S]*?)</sense>"
    )
    val senses = senseRegex.findAll(content).mapIndexed { index, match ->
        val senseContent = match.groupValues[1]

        val partOfSpeech = Regex("<partOfSpeech>([\\s\\S]*?)</partOfSpeech>").find(senseContent)
            ?.groupValues?.get(1)?.trim() ?: ""
        val chineseMeaning = Regex("<chineseMeaning>([\\s\\S]*?)</chineseMeaning>").find(senseContent)
            ?.groupValues?.get(1)?.trim() ?: ""
        val englishDefinition =
            Regex("<englishDefinition>([\\s\\S]*?)</englishDefinition>").find(senseContent)
                ?.groupValues?.get(1)?.trim() ?: ""

        val exampleRegex = Regex("<example>([\\s\\S]*?)</example>")
        val examples = exampleRegex.findAll(senseContent).mapIndexed { exIndex, exMatch ->
            val exContent = exMatch.groupValues[1]
            val sentenceEn = Regex("<en>([\\s\\S]*?)</en>").find(exContent)
                ?.groupValues?.get(1)?.trim() ?: ""
            val sentenceZh = Regex("<zh>([\\s\\S]*?)</zh>").find(exContent)
                ?.groupValues?.get(1)?.trim() ?: ""
            ExampleSentence(
                id = 0L,
                orderIndex = exIndex + 1,
                sentenceEn = sentenceEn,
                sentenceZh = sentenceZh,
                isPrimary = exIndex == 0
            )
        }.toList()

        WordSense(
            id = 0L,
            orderIndex = index + 1,
            partOfSpeech = partOfSpeech,
            chineseMeaning = chineseMeaning,
            englishDefinition = englishDefinition,
            examples = examples
        )
    }.toList()

    if (senses.isEmpty()) return null

    return WordDetail(
        wordId = 0L,
        spellingDisplay = spelling,
        phoneticIpa = phonetic,
        primarySense = senses.firstOrNull(),
        allSenses = senses,
        isInVocabulary = false,
        vocabularyEntryId = null
    )
}
