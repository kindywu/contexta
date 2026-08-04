package com.ak.contexta.ui.reading

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 阅读页分词（findWordRanges）测试。
 * 语义与分词参考实现（Python findall: [a-zA-Z]+(?:['-][a-zA-Z]+)*）一致：
 * 兼容缩写、连字符复合词，忽略外围标点，段落末尾不带空格直接跟标点的单词也能完整提取。
 */
class ReadingWordExtractionTest {

    private fun wordsOf(text: String): List<String> =
        findWordRanges(text).map { text.substring(it) }

    @Test
    fun `extracts contractions hyphenated compounds and punctuation-glued words`() {
        // 复杂测试段落（同参考实现，弯引号/弯撇号已规范化为 ASCII）：
        // 引号、括号、破折号、缩写、粘连标点、复合词、多符号混杂
        val complexText = """
When you're chasing your dreams, don't fear temporary failures—they aren't permanent roadblocks.
The state-of-the-art device, designed by young engineers, can fix most common bugs: lag, crash, overload.
"I've tried dozens of methods," she said, "but nobody's solution works better than simple persistence."
Humanity's greatest strength isn't talent, but our never-give-up spirit!
Tomorrow's plan: review notes, finish homework, join the after-school club.
"""
        val words = wordsOf(complexText)
        val expected = listOf(
            "When", "you're", "chasing", "your", "dreams", "don't", "fear", "temporary",
            "failures", "they", "aren't", "permanent", "roadblocks",
            "The", "state-of-the-art", "device", "designed", "by", "young", "engineers",
            "can", "fix", "most", "common", "bugs", "lag", "crash", "overload",
            "I've", "tried", "dozens", "of", "methods", "she", "said", "but", "nobody's",
            "solution", "works", "better", "than", "simple", "persistence",
            "Humanity's", "greatest", "strength", "isn't", "talent", "but", "our",
            "never-give-up", "spirit",
            "Tomorrow's", "plan", "review", "notes", "finish", "homework", "join",
            "the", "after-school", "club"
        )
        assertEquals(expected, words)
    }

    @Test
    fun `paragraph final words with trailing punctuation are extracted`() {
        // 回归：段落最后一个单词后面无空格直接跟标点（修复前 token 带标点导致不可点击）
        val text = "Learn a new word every day. Practice makes progress."
        assertEquals(
            listOf("Learn", "a", "new", "word", "every", "day", "Practice", "makes", "progress"),
            wordsOf(text)
        )
    }

    @Test
    fun `lone punctuation and dashes are not words`() {
        assertEquals(emptyList<String>(), wordsOf("—"))
        assertEquals(emptyList<String>(), wordsOf("-"))
        assertEquals(emptyList<String>(), wordsOf("'"))
        assertEquals(emptyList<String>(), wordsOf("\"'--\""))
    }

    @Test
    fun `word ranges reconstruct the original text without losing characters`() {
        val text = "Hello, world! (\"I'm fine.\") — Really?\"OK\""
        val rebuilt = buildString {
            var cursor = 0
            for (range in findWordRanges(text)) {
                append(text.substring(cursor, range.first))
                append(text.substring(range))
                cursor = range.last + 1
            }
            append(text.substring(cursor))
        }
        assertEquals(text, rebuilt)
    }
}
