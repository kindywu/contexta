package com.ak.contexta.ui.addword

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ak.contexta.domain.model.WordSense
import com.ak.contexta.ui.components.AppButton
import com.ak.contexta.ui.components.AppButtonVariant
import com.ak.contexta.ui.components.AppCard
import com.ak.contexta.ui.components.AppTopBar
import com.ak.contexta.ui.components.LoadingIndicator
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.BodyText
import com.ak.contexta.ui.theme.Error
import com.ak.contexta.ui.theme.Hairline
import com.ak.contexta.ui.theme.Ink
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.MutedSoft
import com.ak.contexta.ui.theme.PhoneticStyle
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.Success
import com.ak.contexta.ui.theme.SurfaceSoft

@Composable
fun AddWordScreen(
    onBack: () -> Unit,
    viewModel: AddWordViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        AppTopBar(title = "录入单词", onBack = onBack)

        if (state.success != null) {
            AddWordResultContent(
                success = state.success!!,
                onAddAnother = { viewModel.reset() },
                onDone = onBack
            )
        } else {
            AddWordInputContent(
                state = state,
                onInputChange = viewModel::onInputChange,
                onSubmit = viewModel::submit,
                onRetry = viewModel::submit
            )
        }
    }
}

@Composable
private fun AddWordInputContent(
    state: AddWordUiState,
    onInputChange: (String) -> Unit,
    onSubmit: () -> Unit,
    onRetry: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        AppCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = "输入英文单词",
                    style = MaterialTheme.typography.headlineMedium
                )
                Spacer(modifier = Modifier.height(12.dp))
                OutlinedTextField(
                    value = state.input,
                    onValueChange = onInputChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("例如：serendipity", color = MutedSoft) },
                    singleLine = true,
                    shape = RoundedCornerShape(8.dp),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { onSubmit() }),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Primary,
                        unfocusedBorderColor = Hairline,
                        focusedContainerColor = Background,
                        unfocusedContainerColor = Background
                    )
                )
                Spacer(modifier = Modifier.height(16.dp))
                AppButton(
                    text = "生成释义并加入生词库",
                    onClick = onSubmit,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = state.input.isNotBlank() && !state.isSubmitting
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "本地词库没有该词时，将调用 AI 生成音标、释义与例句",
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted
                )
            }
        }

        state.invalidInput?.let { message ->
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = Error
            )
        }

        state.error?.let { message ->
            Spacer(modifier = Modifier.height(12.dp))
            AppCard() {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = BodyText
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    AppButton(text = "重试", onClick = onRetry)
                }
            }
        }

        if (state.isSubmitting) {
            Spacer(modifier = Modifier.height(24.dp))
            LoadingIndicator(
                message = state.stageMessage ?: "处理中…",
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun AddWordResultContent(
    success: AddWordSuccessData,
    onAddAnother: () -> Unit,
    onDone: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        // 加入状态徽标
        AppCard() {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (success.addedToVocabulary) {
                    Icon(
                        imageVector = Icons.Outlined.CheckCircle,
                        contentDescription = null,
                        tint = Success,
                        modifier = Modifier.size(20.dp)
                    )
                } else {
                    Text(
                        text = "•",
                        style = MaterialTheme.typography.titleMedium,
                        color = Muted
                    )
                }
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = when {
                        success.addedToVocabulary && success.alreadyExisted ->
                            "已加入生词库（复用本地词库释义）"
                        success.addedToVocabulary -> "已加入生词库"
                        else -> "该词已在生词库中"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (success.addedToVocabulary) Success else BodyText,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // 单词详情卡片
        AppCard() {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = success.word,
                    style = MaterialTheme.typography.headlineLarge
                )
                if (success.phonetic != null) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = success.phonetic,
                        style = PhoneticStyle
                    )
                }

                success.senses.forEach { sense ->
                    Spacer(modifier = Modifier.height(16.dp))
                    SenseBlock(sense)
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        AppButton(
            text = "再录一个",
            onClick = onAddAnother,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(8.dp))
        AppButton(
            text = "返回生词本",
            onClick = onDone,
            modifier = Modifier.fillMaxWidth(),
            variant = AppButtonVariant.Secondary
        )
    }
}

@Composable
private fun SenseBlock(sense: WordSense) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(SurfaceSoft)
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Text(
                text = sense.partOfSpeech,
                style = MaterialTheme.typography.labelLarge,
                color = Primary,
                modifier = Modifier.padding(top = 2.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = sense.chineseMeaning,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = Ink
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = sense.englishDefinition,
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted
                )
            }
        }

        sense.examples.forEach { example ->
            Spacer(modifier = Modifier.height(10.dp))
            Column {
                Text(
                    text = example.sentenceEn,
                    style = MaterialTheme.typography.bodySmall,
                    color = BodyText
                )
                Text(
                    text = example.sentenceZh,
                    style = MaterialTheme.typography.bodySmall,
                    color = MutedSoft
                )
            }
        }
    }
}
