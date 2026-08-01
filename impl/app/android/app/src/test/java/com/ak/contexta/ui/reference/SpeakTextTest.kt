package com.ak.contexta.ui.reference

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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

    // ─── phoneme own-sound mapping ───

    @Test
    fun `every phoneme in the reference grid has a sound mapping`() {
        val phones = phonicsGroups.flatMap { it.items }.map { it.phone }
        assertEquals(48, phones.size)
        phones.forEach { phone ->
            assertNotNull("missing own-sound mapping for $phone", phonemeOwnSound(phone))
        }
    }

    @Test
    fun `own-sound spot checks`() {
        assertEquals("ee", phonemeOwnSound("/iː/"))
        assertEquals("ack", phonemeOwnSound("/æ/"))
        assertEquals("buh", phonemeOwnSound("/b/"))
        assertEquals("eye", phonemeOwnSound("/aɪ/"))
        assertEquals("nguh", phonemeOwnSound("/ŋ/"))
    }

    @Test
    fun `unknown phoneme returns null`() {
        assertNull(phonemeOwnSound("/zzz/"))
    }

    @Test
    fun `phonetic cell own sound uses mapping with example fallback`() {
        val cell = ReferenceCellData(
            char = "/iː/", reading = "单元音 (12)", example = "see", exampleCn = "", isPhonetic = true
        )
        assertEquals("ee", ownSoundFor(cell))
        val unknown = ReferenceCellData(
            char = "/??/", reading = "x", example = "see", exampleCn = "", isPhonetic = true
        )
        assertEquals("see", ownSoundFor(unknown))
    }

    @Test
    fun `alphabet cell own sound is letter name`() {
        val cell = ReferenceCellData(
            char = "A a", reading = "/eɪ/", example = "Apple", exampleCn = "苹果", isPhonetic = false
        )
        assertEquals("A", ownSoundFor(cell))
    }
}
