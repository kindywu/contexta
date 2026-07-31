package com.ak.contexta.ui.addword

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import com.ak.contexta.ui.components.LoadingIndicator
import com.ak.contexta.ui.theme.Accent
import com.ak.contexta.ui.theme.AccentOn
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Border
import com.ak.contexta.ui.theme.Danger
import com.ak.contexta.ui.theme.Foreground
import com.ak.contexta.ui.theme.ForegroundSecondary
import com.ak.contexta.ui.theme.Meta
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.Success
import com.ak.contexta.ui.theme.Surface
import com.ak.contexta.ui.theme.SurfaceWarm

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
        AddWordHeader(onBack = onBack)

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
private fun AddWordHeader(onBack: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Surface)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "←",
            style = MaterialTheme.typography.titleLarge,
            color = Accent,
            modifier = Modifier.clickable { onBack() }
        )
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = "录入单词",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold
        )
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
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = Surface)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "输入英文单词",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(12.dp))
                OutlinedTextField(
                    value = state.input,
                    onValueChange = onInputChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("例如：serendipity", color = Meta) },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { onSubmit() }),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Accent,
                        unfocusedBorderColor = Border,
                        focusedContainerColor = Background,
                        unfocusedContainerColor = Background
                    )
                )
                Spacer(modifier = Modifier.height(16.dp))
                Button(
                    onClick = onSubmit,
                    enabled = state.input.isNotBlank() && !state.isSubmitting,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Accent,
                        contentColor = AccentOn
                    )
                ) {
                    Text("生成释义并加入生词库")
                }
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
                color = Danger
            )
        }

        state.error?.let { message ->
            Spacer(modifier = Modifier.height(12.dp))
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = SurfaceWarm)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = ForegroundSecondary
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Button(
                        onClick = onRetry,
                        shape = RoundedCornerShape(10.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Accent,
                            contentColor = AccentOn
                        )
                    ) {
                        Text("重试")
                    }
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
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(
                containerColor = if (success.addedToVocabulary) Success else SurfaceWarm
            )
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (success.addedToVocabulary) "✓" else "•",
                    style = MaterialTheme.typography.titleMedium,
                    color = if (success.addedToVocabulary) Success else Muted
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = when {
                        success.addedToVocabulary && success.alreadyExisted ->
                            "已加入生词库（复用本地词库释义）"
                        success.addedToVocabulary -> "已加入生词库"
                        else -> "该词已在生词库中"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (success.addedToVocabulary) Success else ForegroundSecondary,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // 单词详情卡片
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = Surface)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = success.word,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold
                )
                if (success.phonetic != null) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = success.phonetic,
                        style = MaterialTheme.typography.bodyLarge,
                        color = Meta
                    )
                }

                success.senses.forEach { sense ->
                    Spacer(modifier = Modifier.height(16.dp))
                    SenseBlock(sense)
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = onAddAnother,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Accent,
                contentColor = AccentOn
            )
        ) {
            Text("再录一个")
        }
        Spacer(modifier = Modifier.height(8.dp))
        Button(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = SurfaceWarm,
                contentColor = Foreground
            )
        ) {
            Text("返回生词本")
        }
    }
}

@Composable
private fun SenseBlock(sense: WordSense) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(Background)
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Text(
                text = sense.partOfSpeech,
                style = MaterialTheme.typography.labelLarge,
                color = Accent,
                modifier = Modifier.padding(top = 2.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = sense.chineseMeaning,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = Foreground
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
                    color = ForegroundSecondary
                )
                Text(
                    text = example.sentenceZh,
                    style = MaterialTheme.typography.bodySmall,
                    color = Meta
                )
            }
        }
    }
}
