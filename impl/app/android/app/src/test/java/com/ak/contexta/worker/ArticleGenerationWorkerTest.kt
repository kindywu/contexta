package com.ak.contexta.worker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ArticleGenerationWorkerTest {

    @Test
    fun `parseLlmResponse extracts title and paragraphs from realistic LLM output`() {
        // Simulates what DeepSeek would return for a DAILY_CONVERSATION article
        val xml = """<title>Morning Coffee Chat</title>
<paragraph>Good morning, Lisa! Did you sleep well last night?</paragraph>
<translation>早上好，丽莎！你昨晚睡得好吗？</translation>
<paragraph>Yes, thank you! I went to bed early and had a wonderful rest.</paragraph>
<translation>是的，谢谢！我早早睡了，休息得很好。</translation>
<paragraph>That is great to hear. Would you like to grab a cup of coffee together?</paragraph>
<translation>很高兴听你这么说。你想一起去喝杯咖啡吗？</translation>
<paragraph>Sure, I would love to! There is a new cafe around the corner that I have been wanting to try.</paragraph>
<translation>当然，我很想去！拐角处新开了一家咖啡馆，我一直想去试试。</translation>"""

        val (title, paragraphs) = parseLlmResponse(xml)

        assertEquals("Morning Coffee Chat", title)
        assertEquals(4, paragraphs.size)
        // First paragraph
        assertEquals("Good morning, Lisa! Did you sleep well last night?", paragraphs[0].englishText)
        assertEquals("早上好，丽莎！你昨晚睡得好吗？", paragraphs[0].chineseTranslation)
        assertEquals(1, paragraphs[0].orderIndex)
        // Last paragraph
        assertEquals("Sure, I would love to! There is a new cafe around the corner that I have been wanting to try.", paragraphs[3].englishText)
        assertEquals("当然，我很想去！拐角处新开了一家咖啡馆，我一直想去试试。", paragraphs[3].chineseTranslation)
        assertEquals(4, paragraphs[3].orderIndex)
    }

    @Test
    fun `parseLlmResponse parses full article with eight paragraphs`() {
        // Simulates realistic LLM output for SCENE_DESCRIPTION article
        val xml = """<title>A Walk in the Park</title>
<paragraph>The sun was just beginning to rise over the horizon, casting a warm golden glow across the entire park.</paragraph>
<translation>太阳刚刚开始从地平线升起，将温暖的金色光芒洒满整个公园。</translation>
<paragraph>Birds were chirping happily in the trees, and a gentle breeze was blowing through the leaves.</paragraph>
<translation>鸟儿在树上欢快地歌唱，微风吹过树叶。</translation>
<paragraph>An elderly couple was walking hand in hand along the winding path, enjoying the peaceful morning.</paragraph>
<translation>一对老夫妇手牵着手沿着蜿蜒的小路散步，享受着宁静的早晨。</translation>
<paragraph>Children were laughing and playing on the grassy field while their parents sat on nearby benches watching them.</paragraph>
<translation>孩子们在草地上欢笑玩耍，父母则坐在附近的长椅上看着他们。</translation>
<paragraph>A young woman was jogging with her dog, a golden retriever that seemed full of endless energy.</paragraph>
<translation>一位年轻女子带着她的狗慢跑，那是一只似乎有无穷活力的金毛寻回犬。</translation>
<paragraph>The pond at the center of the park reflected the blue sky like a perfect mirror.</paragraph>
<translation>公园中央的池塘像一面完美的镜子，映照着蓝天。</translation>
<paragraph>Ducks were swimming gracefully across the water, leaving tiny ripples behind them.</paragraph>
<translation>鸭子在水中优雅地游过，身后留下细小的涟漪。</translation>
<paragraph>It was a perfect start to a beautiful day, and everyone in the park seemed to feel the same way.</paragraph>
<translation>这是美好一天的完美开始，公园里的每个人似乎都有同感。</translation>"""

        val (title, paragraphs) = parseLlmResponse(xml)

        assertEquals("A Walk in the Park", title)
        assertEquals(8, paragraphs.size)
        // Verify real article content structure
        assertEquals("The sun was just beginning to rise over the horizon, casting a warm golden glow across the entire park.", paragraphs[0].englishText)
        assertEquals("Ducks were swimming gracefully across the water, leaving tiny ripples behind them.", paragraphs[6].englishText)
        assertEquals("第8段的翻译应该是最后一句", paragraphs[7].chineseTranslation, "这是美好一天的完美开始，公园里的每个人似乎都有同感。")
        // Verify order indices
        for (i in paragraphs.indices) {
            assertEquals("orderIndex should be ${i + 1}", i + 1, paragraphs[i].orderIndex)
        }
    }

    @Test
    fun `parseLlmResponse defaults to Untitled when title tag is missing`() {
        // Edge case: LLM occasionally omits the title tag
        val xml = """<paragraph>Hello world.</paragraph>
<translation>你好世界。</translation>"""

        val (title, paragraphs) = parseLlmResponse(xml)

        assertEquals("Untitled", title)
        assertEquals(1, paragraphs.size)
    }

    @Test
    fun `parseLlmResponse handles empty content`() {
        val (title, paragraphs) = parseLlmResponse("")

        assertEquals("Untitled", title)
        assertTrue(paragraphs.isEmpty())
    }

    @Test
    fun `parseLlmResponse handles content with no XML tags`() {
        // LLM might sometimes return plain text without XML
        val (title, paragraphs) = parseLlmResponse("Just some plain text without any tags.")

        assertEquals("Untitled", title)
        assertTrue(paragraphs.isEmpty())
    }

    @Test
    fun `parseLlmResponse handles mismatched paragraph and translation counts`() {
        // LLM occasionally returns fewer translations than paragraphs
        val xml = """<title>Test</title>
<paragraph>First paragraph.</paragraph>
<translation>第一段翻译。</translation>
<paragraph>Second paragraph.</paragraph>
<paragraph>Third paragraph.</paragraph>"""

        val (title, paragraphs) = parseLlmResponse(xml)

        assertEquals("Test", title)
        assertEquals(3, paragraphs.size)
        // Second and third paragraphs have no matching translations
        assertEquals("第一段翻译。", paragraphs[0].chineseTranslation)
        assertEquals("", paragraphs[1].chineseTranslation)
        assertEquals("", paragraphs[2].chineseTranslation)
    }

    @Test
    fun `parseLlmResponse trims whitespace from titles and paragraphs`() {
        val xml = """<title>  Spaced Out Title  </title>
<paragraph>   Sentence with spaces.   </paragraph>
<translation>   带空格的句子。  </translation>"""

        val (title, paragraphs) = parseLlmResponse(xml)

        assertEquals("Spaced Out Title", title)
        assertEquals("Sentence with spaces.", paragraphs[0].englishText)
        assertEquals("带空格的句子。", paragraphs[0].chineseTranslation)
    }

    @Test
    fun `parseLlmResponse handles multiline content inside tags`() {
        // LLM responses may contain line breaks within tags
        val xml = """<title>Multi-line</title>
<paragraph>This is a paragraph
that spans multiple lines
in the LLM response.</paragraph>
<translation>这是一个
跨越多行的段落。</translation>"""

        val (title, paragraphs) = parseLlmResponse(xml)

        assertEquals("Multi-line", title)
        assertEquals("This is a paragraph\nthat spans multiple lines\nin the LLM response.", paragraphs[0].englishText)
        assertEquals("这是一个\n跨越多行的段落。", paragraphs[0].chineseTranslation)
    }

    @Test
    fun `parseLlmResponse handles title with punctuation and special characters`() {
        val xml = """<title>Don't Stop Me Now! (feat. Queen)</title>
<paragraph>Music is great.</paragraph>
<translation>音乐很棒。</translation>"""

        val (title, _) = parseLlmResponse(xml)
        assertEquals("Don't Stop Me Now! (feat. Queen)", title)
    }

    @Test
    fun `parseLlmResponse handles only translations without paragraphs`() {
        val xml = """<title>Only Translations</title>
<translation>只有翻译。</translation>
<translation>没有原文。</translation>"""

        val (title, paragraphs) = parseLlmResponse(xml)

        assertEquals("Only Translations", title)
        assertTrue(paragraphs.isEmpty())
    }

    @Test
    fun `parseLlmResponse orderIndex starts at 1 and increments sequentially`() {
        val xml = """<title>Order Test</title>
<paragraph>A</paragraph>
<translation>甲</translation>
<paragraph>B</paragraph>
<translation>乙</translation>
<paragraph>C</paragraph>
<translation>丙</translation>"""

        val (_, paragraphs) = parseLlmResponse(xml)

        assertEquals(1, paragraphs[0].orderIndex)
        assertEquals(2, paragraphs[1].orderIndex)
        assertEquals(3, paragraphs[2].orderIndex)
    }
}
