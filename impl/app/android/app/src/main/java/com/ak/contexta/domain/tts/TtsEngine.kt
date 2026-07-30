package com.ak.contexta.domain.tts

/**
 * TTS 引擎接口，由 data 层实现。
 */
interface TtsEngine {
    /** Whether a TTS engine is available and ready. */
    fun isAvailable(): Boolean

    /** Human-readable description of why TTS is unavailable, or null if available. */
    fun unavailabilityReason(): String?

    /** Speak a word/phrase, stopping any current utterance. Returns true if spoken. */
    fun speak(text: String, speed: Float = 1.0f): Boolean

    /** Stop any current utterance. */
    fun stop()
}
