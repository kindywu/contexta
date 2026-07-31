package com.ak.contexta.ui.reference

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GrammarDataTest {

    @Test
    fun `grammarGroups has three theme groups with correct names and counts`() {
        assertEquals(listOf("时态", "词形变化", "功能词"), grammarGroups.map { it.name })
        assertEquals(listOf(5, 2, 3), grammarGroups.map { it.items.size })
    }

    @Test
    fun `all grammar items have complete fields and paired examples`() {
        val all = grammarGroups.flatMap { it.items }
        assertEquals(10, all.size)
        all.forEach { item ->
            assertTrue(item.name.isNotBlank())
            assertTrue(item.explanation.isNotBlank())
            assertTrue(item.chineseExplanation.isNotBlank())
            assertTrue(item.examples.isNotEmpty())
            item.examples.forEach { (en, zh) ->
                assertTrue(en.isNotBlank())
                assertTrue(zh.isNotBlank())
            }
        }
    }
}
