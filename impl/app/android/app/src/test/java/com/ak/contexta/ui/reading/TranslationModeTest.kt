package com.ak.contexta.ui.reading

import org.junit.Assert.assertEquals
import org.junit.Test

class TranslationModeTest {

    @Test
    fun `cycle order is FULL to DIM to BLURRED to HIDDEN back to FULL`() {
        assertEquals(TranslationMode.DIM, TranslationMode.FULL.next)
        assertEquals(TranslationMode.BLURRED, TranslationMode.DIM.next)
        assertEquals(TranslationMode.HIDDEN, TranslationMode.BLURRED.next)
        assertEquals(TranslationMode.FULL, TranslationMode.HIDDEN.next)
    }
}
