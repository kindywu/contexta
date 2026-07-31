package com.ak.contexta.ui.addword

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.domain.model.WordSense
import com.ak.contexta.domain.usecase.AddWordUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AddWordUiState(
    val input: String = "",
    val isSubmitting: Boolean = false,
    val stageMessage: String? = null,
    val success: AddWordSuccessData? = null,
    val error: String? = null,
    val invalidInput: String? = null
)

data class AddWordSuccessData(
    val word: String,
    val phonetic: String?,
    val senses: List<WordSense>,
    val alreadyExisted: Boolean,
    val addedToVocabulary: Boolean
)

@HiltViewModel
class AddWordViewModel @Inject constructor(
    private val addWordUseCase: AddWordUseCase
) : ViewModel() {

    private val _state = MutableStateFlow(AddWordUiState())
    val state: StateFlow<AddWordUiState> = _state.asStateFlow()

    fun onInputChange(value: String) {
        _state.value = _state.value.copy(
            input = value,
            invalidInput = null,
            error = null,
            success = null
        )
    }

    fun submit() {
        val input = _state.value.input
        if (input.isBlank() || _state.value.isSubmitting) return

        _state.value = _state.value.copy(
            isSubmitting = true,
            invalidInput = null,
            error = null,
            success = null,
            stageMessage = "正在检查本地词库…"
        )

        viewModelScope.launch {
            val result = addWordUseCase(input) { stage ->
                _state.value = _state.value.copy(
                    stageMessage = when (stage) {
                        AddWordUseCase.Stage.CHECKING_LOCAL -> "正在检查本地词库…"
                        AddWordUseCase.Stage.GENERATING -> "正在通过 AI 生成音标、释义与例句…"
                    }
                )
            }

            when (result) {
                is AddWordUseCase.AddWordResult.Success -> _state.value = _state.value.copy(
                    isSubmitting = false,
                    stageMessage = null,
                    success = result.toUiData(alreadyExisted = false)
                )
                is AddWordUseCase.AddWordResult.AlreadyExists -> _state.value = _state.value.copy(
                    isSubmitting = false,
                    stageMessage = null,
                    success = result.toUiData(alreadyExisted = true)
                )
                is AddWordUseCase.AddWordResult.InvalidInput -> _state.value = _state.value.copy(
                    isSubmitting = false,
                    stageMessage = null,
                    invalidInput = result.message
                )
                is AddWordUseCase.AddWordResult.Failed -> _state.value = _state.value.copy(
                    isSubmitting = false,
                    stageMessage = null,
                    error = result.message
                )
            }
        }
    }

    /** 清空状态，录入下一个单词。 */
    fun reset() {
        _state.value = AddWordUiState()
    }

    private fun AddWordUseCase.AddWordResult.Success.toUiData(alreadyExisted: Boolean) =
        AddWordSuccessData(
            word = detail.spellingDisplay,
            phonetic = detail.phoneticIpa,
            senses = detail.allSenses,
            alreadyExisted = alreadyExisted,
            addedToVocabulary = addedToVocabulary
        )

    private fun AddWordUseCase.AddWordResult.AlreadyExists.toUiData(alreadyExisted: Boolean) =
        AddWordSuccessData(
            word = detail.spellingDisplay,
            phonetic = detail.phoneticIpa,
            senses = detail.allSenses,
            alreadyExisted = alreadyExisted,
            addedToVocabulary = addedToVocabulary
        )
}
