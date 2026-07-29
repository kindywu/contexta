package com.ak.contexta.domain.tts

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages Android Text-To-Speech for word and paragraph pronunciation.
 *
 * On Xiaomi devices the built-in TTS engine (com.xiaomi.mibrain.speech) may
 * not be discovered via the default TextToSpeech(context) constructor, so
 * we try three engine strategies in sequence:
 * 1. Explicit engine package  —  com.xiaomi.mibrain.speech
 * 2. Explicit engine package  —  com.google.android.tts  (Google TTS)
 * 3. Default (system-chosen) engine
 *
 * The first one that initialises successfully is kept.
 */
@Singleton
class TtsManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var failureMessage: String? = null
    private var pendingText: String? = null

    private val engineCandidates = listOf(
        "com.xiaomi.mibrain.speech",
        "com.google.android.tts",
        null  // fallback: system default
    )

    init {
        Handler(Looper.getMainLooper()).post {
            tryEngines(0)
        }
    }

    /** Try each engine candidate until one succeeds. */
    private fun tryEngines(index: Int) {
        if (index >= engineCandidates.size) {
            val msg = "No TTS engine could be initialized"
            failureMessage = msg
            Log.w(TAG, msg)
            return
        }
        val pkg = engineCandidates[index]
        Log.i(TAG, "Trying TTS engine #$index: ${pkg ?: "(system default)"}")
        val listener = TextToSpeech.OnInitListener { status ->
            if (status == TextToSpeech.SUCCESS) {
                onEngineReady()
            } else {
                Log.w(TAG, "Engine #$index (${pkg ?: "default"}) failed status=$status")
                tts?.shutdown()
                tts = null
                tryEngines(index + 1)
            }
        }
        try {
            tts = if (pkg != null) {
                TextToSpeech(context, listener, pkg)
            } else {
                TextToSpeech(context, listener)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Engine #$index (${pkg ?: "default"}) threw: ${e.message}")
            tryEngines(index + 1)
        }
    }

    private fun onEngineReady() {
        tts?.language = Locale.ENGLISH
        ready = true
        Log.i(TAG, "TTS engine ready")

        pendingText?.let { text ->
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, null)
            pendingText = null
        }
    }

    /** Whether a TTS engine is available and ready. */
    fun isAvailable(): Boolean = ready

    /** Human-readable description of why TTS is unavailable, or null if available. */
    fun unavailabilityReason(): String? = failureMessage

    /** Speak a word/phrase, stopping any current utterance. Returns true if spoken. */
    @Suppress("DEPRECATION")
    @Synchronized
    fun speak(text: String, speed: Float = 1.0f): Boolean {
        if (ready) {
            return try {
                tts?.setSpeechRate(speed)
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, null)
                true
            } catch (e: Exception) {
                Log.w(TAG, "TTS speak failed for '$text': ${e.message}")
                false
            }
        }
        if (failureMessage == null) {
            pendingText = text
            return true
        }
        return false
    }

    /** Stop any current utterance. */
    fun stop() {
        try {
            tts?.stop()
        } catch (_: Exception) { }
    }

    companion object {
        private const val TAG = "TtsManager"
    }
}
