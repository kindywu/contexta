package com.ak.contexta.domain.tts

/**
 * TTS 引擎接口，由 data 层实现。
 */
interface TtsEngine {
    /** Whether a TTS engine is available and ready. */
    fun isAvailable(): Boolean

    /** Human-readable description of why TTS is unavailable, or null if available. */
    fun unavailabilityReason(): String?

    /** Speak a word/phrase, stopping any current utterance. Returns the utterance id if spoken, null on failure. */
    fun speak(text: String, speed: Float = 1.0f): String?

    /** Stop any current utterance. */
    fun stop()

    /**
     * Register a callback fired when the current utterance finishes — either
     * naturally (onDone), by [stop], or because it was interrupted by a new
     * utterance (onStop/onError). Invoked on the main thread, with the id of
     * the utterance that ended. Pass null to unregister.
     */
    fun setOnSpeakingFinished(callback: ((utteranceId: String?) -> Unit)?)
}
