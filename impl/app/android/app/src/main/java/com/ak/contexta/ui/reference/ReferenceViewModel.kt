package com.ak.contexta.ui.reference

import androidx.lifecycle.ViewModel
import com.ak.contexta.domain.tts.TtsManager
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

@HiltViewModel
class ReferenceViewModel @Inject constructor(
    private val ttsManager: TtsManager
) : ViewModel() {

    /**
     * Speak the given text using TTS.
     */
    fun speak(text: String) {
        ttsManager.speak(text)
    }
}
