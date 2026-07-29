package com.ak.contexta.domain.generation

/**
 * Loads prompt template files from classpath resources (`src/main/resources/prompts/`).
 *
 * Templates can contain sections delimited by `=== SECTION_NAME ===` markers.
 * Use [loadSection] to extract sections and substitute `{{key}}` placeholders.
 *
 * File layout:
 * ```
 * === COMMON ===
 * shared content
 *
 * === LOW ===
 * difficulty-specific content
 *
 * === USER_PROMPT ===
 * template for user prompt
 * ```
 */
object PromptLoader {

    private const val PROMPTS_DIR = "prompts/"
    private val SECTION_REGEX = Regex("""=== (\w+) ===\s*\n?(.*?)(?=\n=== |\Z)""", RegexOption.DOT_MATCHES_ALL)

    /**
     * Load a raw template file from the classpath.
     *
     * @param fileName filename under `prompts/` (e.g. `"article_system.txt"`)
     * @param fallback text to use if the file cannot be loaded
     * @return file content, or [fallback] if loading fails
     */
    fun load(fileName: String, fallback: String): String {
        val url = PromptLoader::class.java.classLoader?.getResource("$PROMPTS_DIR$fileName")
            ?: ClassLoader.getSystemResource("$PROMPTS_DIR$fileName")

        return if (url != null) {
            try {
                url.readText().trimEnd()
            } catch (e: Exception) {
                fallback
            }
        } else {
            fallback
        }
    }

    /**
     * Load one or more named sections from a template file and concatenate them.
     *
     * @param fileName filename under `prompts/`
     * @param sections section names in order (e.g. `listOf("COMMON", "LOW")`)
     * @param params key-value pairs for `{{key}}` substitution across all selected sections
     * @param fallback returned if the file or any requested section is missing
     */
    fun loadSection(
        fileName: String,
        sections: List<String>,
        params: Map<String, String> = emptyMap(),
        fallback: String
    ): String {
        val content = load(fileName, fallback)
        if (content == fallback) return fallback

        // Parse all sections into a map
        val sectionMap = mutableMapOf<String, String>()
        for (match in SECTION_REGEX.findAll(content)) {
            sectionMap[match.groupValues[1]] = match.groupValues[2].trim()
        }

        // Build result from requested sections
        val parts = sections.mapNotNull { sectionMap[it] }
        if (parts.isEmpty()) return fallback

        var result = parts.joinToString("\n\n")

        // Substitute parameters
        for ((key, value) in params) {
            result = result.replace("{{${key}}}", value)
        }

        return result
    }
}
