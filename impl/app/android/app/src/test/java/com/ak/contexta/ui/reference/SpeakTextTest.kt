package com.ak.contexta.ui.reference

import org.junit.Assert.assertEquals
import org.junit.Test

class SpeakTextTest {

    @Test
    fun `alphabet cell speaks letter name then example`() {
        val cell = ReferenceCellData(
            char = "A a", reading = "/eɪ/", example = "Apple", exampleCn = "苹果", isPhonetic = false
        )
        assertEquals("A. Apple", speakTextFor(cell))
    }

    @Test
    fun `multi-letter char uses uppercase first letter`() {
        val w = ReferenceCellData(
            char = "W w", reading = "/ˈdʌbljuː/", example = "Water", exampleCn = "水", isPhonetic = false
        )
        assertEquals("W. Water", speakTextFor(w))
        val x = ReferenceCellData(
            char = "X x", reading = "/eks/", example = "X-ray", exampleCn = "X光", isPhonetic = false
        )
        assertEquals("X. X-ray", speakTextFor(x))
    }

    @Test
    fun `phonetic cell speaks example only`() {
        val cell = ReferenceCellData(
            char = "/eɪ/", reading = "单元音 (12)", example = "see", exampleCn = "", isPhonetic = true
        )
        assertEquals("see", speakTextFor(cell))
    }
}
