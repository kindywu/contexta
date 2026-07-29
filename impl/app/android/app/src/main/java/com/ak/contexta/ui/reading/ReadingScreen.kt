package com.ak.contexta.ui.reading

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.components.EmptyState
import com.ak.contexta.ui.components.LoadingIndicator
import com.ak.contexta.ui.theme.Accent
import com.ak.contexta.ui.theme.AccentOn
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Foreground
import com.ak.contexta.ui.theme.ForegroundSecondary
import com.ak.contexta.ui.theme.Meta
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.Surface
import com.ak.contexta.ui.theme.SurfaceWarm

@Composable
fun ReadingScreen(
    articleId: Long,
    onBack: () -> Unit,
    viewModel: ReadingViewModel = hiltViewModel()
) {
    LaunchedEffect(articleId) {
        viewModel.loadArticle(articleId)
    }

    val state by viewModel.state.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize().background(Background)) {
            // App bar
            ReadingAppBar(
                title = state.title ?: "文章",
                onBack = onBack,
                onTranslationModeToggle = { viewModel.cycleTranslationMode() },
                translationMode = state.translationMode
            )

            // Translation mode indicator bar
            TranslationModeBar(
                mode = state.translationMode,
                onCycle = { viewModel.cycleTranslationMode() }
            )

            // Content
            when {
                state.isLoading -> LoadingIndicator()
                state.error != null -> EmptyState(
                    icon = "⚠️",
                    message = state.error!!,
                    subMessage = "请返回重新选择"
                )
                else -> {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 16.dp)
                    ) {
                        Spacer(modifier = Modifier.height(12.dp))
                        state.paragraphs.forEachIndexed { index, paragraph ->
                            ReadingParagraph(
                                englishText = paragraph.englishText,
                                chineseTranslation = paragraph.chineseTranslation,
                                translationMode = state.translationMode,
                                onWordClick = { word -> viewModel.showWordSheet(word) },
                                onTranslationClick = {
                                    if (state.translationMode == TranslationMode.BLURRED) {
                                        viewModel.revealTranslation(index)
                                    }
                                }
                            )
                        }
                        Spacer(modifier = Modifier.height(24.dp))
                    }
                }
            }

            // Footer
            ReadingFooter(onBack = onBack)
        }

        // Word bottom sheet overlay
        WordBottomSheetOverlay(
            visible = state.isWordSheetVisible,
            data = state.wordSheetData,
            onDismiss = { viewModel.hideWordSheet() }
        )
    }
}

@Composable
private fun ReadingAppBar(
    title: String,
    onBack: () -> Unit,
    onTranslationModeToggle: () -> Unit,
    translationMode: TranslationMode
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Surface)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "←",
            modifier = Modifier.clickable { onBack() },
            style = MaterialTheme.typography.titleLarge,
            color = Foreground
        )
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = "🔊",
            style = MaterialTheme.typography.titleMedium,
            color = Accent
        )
    }
}

@Composable
private fun TranslationModeBar(
    mode: TranslationMode,
    onCycle: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Background)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "译文",
            style = MaterialTheme.typography.labelMedium,
            color = Meta
        )
        Spacer(modifier = Modifier.width(8.dp))
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(Surface)
                .clickable { onCycle() }
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = mode.label,
                style = MaterialTheme.typography.labelMedium,
                color = ForegroundSecondary
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "▾",
                style = MaterialTheme.typography.labelSmall,
                color = Meta
            )
        }
    }
}

@Composable
private fun ReadingParagraph(
    englishText: String,
    chineseTranslation: String,
    translationMode: TranslationMode,
    onWordClick: (String) -> Unit,
    onTranslationClick: () -> Unit
) {
    Column(modifier = Modifier.padding(bottom = 20.dp)) {
        // English text with clickable words
        Text(
            text = englishText,
            style = MaterialTheme.typography.bodyLarge,
            color = Foreground,
            modifier = Modifier.padding(bottom = 4.dp)
        )

        // Chinese translation
        val translationModifier = Modifier.padding(bottom = 4.dp)
        when (translationMode) {
            TranslationMode.FULL -> {
                Text(
                    text = chineseTranslation,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Muted,
                    modifier = translationModifier
                )
            }
            TranslationMode.BLURRED -> {
                Text(
                    text = chineseTranslation,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Muted,
                    modifier = translationModifier.then(
                        Modifier.blur(radius = 4.dp)
                    ).clickable { onTranslationClick() }
                )
            }
            TranslationMode.HIDDEN -> {
                // Hidden: don't show
            }
        }

        // Play button
        Text(
            text = "🔊 朗读本段",
            style = MaterialTheme.typography.labelMedium,
            color = Accent,
            modifier = Modifier.clickable { /* TTS placeholder */ }
        )
    }
}

@Composable
private fun ReadingFooter(onBack: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Surface)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "← 返回列表",
            style = MaterialTheme.typography.labelMedium,
            color = Accent,
            modifier = Modifier.clickable { onBack() }
        )
        Text(
            text = "下一篇 →",
            style = MaterialTheme.typography.labelMedium,
            color = Accent,
            modifier = Modifier.clickable { /* next article placeholder */ }
        )
    }
}

@Composable
private fun WordBottomSheetOverlay(
    visible: Boolean,
    data: WordSheetData?,
    onDismiss: () -> Unit
) {
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(),
        exit = fadeOut()
    ) {
        if (visible && data != null) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.3f))
                    .clickable { onDismiss() }
            ) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
                        .background(Surface)
                        .clickable(enabled = false) {} // prevent dismiss when tapping sheet
                        .padding(horizontal = 20.dp, vertical = 16.dp)
                ) {
                    Column {
                        // Handle bar
                        Box(
                            modifier = Modifier
                                .width(36.dp)
                                .height(4.dp)
                                .clip(RoundedCornerShape(2.dp))
                                .background(SurfaceWarm)
                                .align(Alignment.CenterHorizontally)
                        )
                        Spacer(modifier = Modifier.height(12.dp))

                        // Word header
                        Row(verticalAlignment = Alignment.Bottom) {
                            Text(
                                text = data.word,
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold
                            )
                            if (data.phonetic != null) {
                                Spacer(modifier = Modifier.width(10.dp))
                                Text(
                                    text = data.phonetic,
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = Meta
                                )
                            }
                            Spacer(modifier = Modifier.weight(1f))
                            Text(
                                text = "🔊",
                                style = MaterialTheme.typography.titleMedium,
                                color = Accent,
                                modifier = Modifier.clickable { /* TTS */ }
                            )
                        }

                        // Translation
                        if (data.translation != null) {
                            Text(
                                text = data.translation,
                                style = MaterialTheme.typography.titleMedium,
                                color = ForegroundSecondary,
                                modifier = Modifier.padding(vertical = 8.dp)
                            )
                        }

                        // Definitions
                        if (data.definitions.isNotEmpty()) {
                            Text(
                                text = data.definitions.joinToString("; "),
                                style = MaterialTheme.typography.bodySmall,
                                color = Muted
                            )
                        }

                        // Example
                        if (data.exampleEn != null) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(Background)
                                    .padding(10.dp)
                                    .padding(top = 8.dp)
                            ) {
                                Text(
                                    text = data.exampleEn,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = Foreground
                                )
                                if (data.exampleZh != null) {
                                    Text(
                                        text = data.exampleZh,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = Muted,
                                        modifier = Modifier.padding(top = 4.dp)
                                    )
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(16.dp))

                        // Actions
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            if (data.isInVocabulary) {
                                Button(
                                    onClick = onDismiss,
                                    modifier = Modifier.weight(1f),
                                    shape = RoundedCornerShape(12.dp),
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = SurfaceWarm,
                                        contentColor = Foreground
                                    )
                                ) {
                                    Text("🗑️ 从生词表移除")
                                }
                            } else {
                                Button(
                                    onClick = onDismiss,
                                    modifier = Modifier.weight(1f),
                                    shape = RoundedCornerShape(12.dp),
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = Accent,
                                        contentColor = AccentOn
                                    )
                                ) {
                                    Text("+ 加入生词表")
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(12.dp))
                    }
                }
            }
        }
    }
}
