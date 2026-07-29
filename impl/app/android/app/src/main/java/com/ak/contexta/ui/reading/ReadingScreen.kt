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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
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
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(articleId) {
        viewModel.loadArticle(articleId)
    }

    val state by viewModel.state.collectAsState()

    val context = LocalContext.current

    // Show snackbar when snackbarMessage changes
    LaunchedEffect(state.snackbarMessage) {
        state.snackbarMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearSnackbar()
        }
    }

    // Open TTS settings when requested
    LaunchedEffect(state.openTtsSettings) {
        if (state.openTtsSettings) {
            context.startActivity(viewModel.openTtsSettingsIntent())
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.TopCenter)
        )
        Column(modifier = Modifier.fillMaxSize().background(Background)) {
            // App bar
            ReadingAppBar(
                title = state.title ?: "文章",
                onBack = onBack,
                onTranslationModeToggle = { viewModel.cycleTranslationMode() },
                translationMode = state.translationMode,
                ttsSpeed = state.ttsSpeed,
                onToggleTtsSpeed = { viewModel.toggleTtsSpeed() },
                onPlayFullArticle = { viewModel.playFullArticle() },
                isReadCompleted = state.isReadCompleted,
                onMarkAsRead = { viewModel.markAsRead() }
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
                                isRevealed = index in state.revealedParagraphs,
                                onWordClick = { word -> viewModel.showWordSheet(word) },
                                onTranslationClick = {
                                    if (state.translationMode == TranslationMode.BLURRED) {
                                        viewModel.revealTranslation(index)
                                    }
                                },
                                onPlay = { viewModel.playText(paragraph.englishText) }
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
            onDismiss = { viewModel.hideWordSheet() },
            onAddToVocabulary = { viewModel.addToVocabulary() },
            onRemoveFromVocabulary = { viewModel.removeFromVocabulary() },
            onPlayWord = { viewModel.playWordPronunciation() }
        )
    }
}

@Composable
private fun ReadingAppBar(
    title: String,
    onBack: () -> Unit,
    onTranslationModeToggle: () -> Unit,
    translationMode: TranslationMode,
    ttsSpeed: Float,
    onToggleTtsSpeed: () -> Unit,
    onPlayFullArticle: () -> Unit,
    isReadCompleted: Boolean,
    onMarkAsRead: () -> Unit
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
        // Read status
        if (isReadCompleted) {
            Text(
                text = "✓ 已读",
                style = MaterialTheme.typography.labelSmall,
                color = Muted
            )
        } else {
            Text(
                text = "✓ 标记已读",
                style = MaterialTheme.typography.labelSmall,
                color = Accent,
                modifier = Modifier
                    .clickable { onMarkAsRead() }
                    .padding(horizontal = 4.dp)
            )
        }
        Spacer(modifier = Modifier.width(4.dp))
        // Play full article
        Text(
            text = "🔊",
            style = MaterialTheme.typography.titleMedium,
            color = Accent,
            modifier = Modifier
                .clickable { onPlayFullArticle() }
                .padding(horizontal = 4.dp)
        )
        Spacer(modifier = Modifier.width(4.dp))
        // Speed toggle
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(6.dp))
                .background(if (ttsSpeed < 1.0f) SurfaceWarm else Accent)
                .clickable { onToggleTtsSpeed() }
                .padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Text(
                text = if (ttsSpeed < 1.0f) "0.5x" else "1x",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = if (ttsSpeed < 1.0f) Meta else AccentOn
            )
        }
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
    isRevealed: Boolean = false,
    onWordClick: (String) -> Unit,
    onTranslationClick: () -> Unit,
    onPlay: () -> Unit
) {
    Column(modifier = Modifier.padding(bottom = 20.dp)) {
        // English text row with play icon
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top
        ) {
            // English text with clickable words
            val annotatedString = buildAnnotatedString {
                val words = englishText.split(Regex("(?<=\\s)|(?=\\s)"))
                words.forEach { token ->
                    val isWord = token.matches(Regex("[A-Za-z'-]+"))
                    if (isWord) {
                        val link = LinkAnnotation.Clickable(
                            tag = "word",
                            styles = TextLinkStyles(style = SpanStyle(color = Foreground))
                        ) {
                            onWordClick(token.lowercase())
                        }
                        withLink(link) {
                            withStyle(SpanStyle(color = Foreground)) {
                                append(token)
                            }
                        }
                    } else {
                        append(token)
                    }
                }
            }
            BasicText(
                text = annotatedString,
                style = MaterialTheme.typography.bodyLarge.copy(color = Foreground),
                modifier = Modifier.weight(1f).padding(end = 8.dp)
            )

            // Play icon
            Text(
                text = "🔊",
                style = MaterialTheme.typography.titleMedium,
                color = Accent,
                modifier = Modifier
                    .clickable { onPlay() }
                    .padding(top = 2.dp)
            )
        }

        Spacer(modifier = Modifier.height(4.dp))

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
                if (isRevealed) {
                    Text(
                        text = chineseTranslation,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Muted,
                        modifier = translationModifier.clickable { onTranslationClick() }
                    )
                } else {
                    Text(
                        text = chineseTranslation,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Muted,
                        modifier = translationModifier.then(
                            Modifier.blur(radius = 4.dp)
                        ).clickable { onTranslationClick() }
                    )
                }
            }
            TranslationMode.HIDDEN -> {
                // Hidden: don't show
            }
        }
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
    onDismiss: () -> Unit,
    onAddToVocabulary: () -> Unit,
    onRemoveFromVocabulary: () -> Unit,
    onPlayWord: () -> Unit
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
                            if (data.phonetic != null && !data.isLoading) {
                                Spacer(modifier = Modifier.width(10.dp))
                                Text(
                                    text = data.phonetic,
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = Meta
                                )
                            }
                            Spacer(modifier = Modifier.weight(1f))
                            if (!data.isLoading) {
                                Text(
                                    text = "🔊",
                                    style = MaterialTheme.typography.titleMedium,
                                    color = Accent,
                                    modifier = Modifier.clickable { onPlayWord() }
                                )
                            }
                        }

                        // Loading state
                        if (data.isLoading) {
                            Spacer(modifier = Modifier.height(20.dp))
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    strokeWidth = 2.dp,
                                    color = Accent
                                )
                                Spacer(modifier = Modifier.width(12.dp))
                                Text(
                                    text = "正在查询…",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = Muted
                                )
                            }
                            Spacer(modifier = Modifier.height(20.dp))
                            return@Column
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
                                    onClick = onRemoveFromVocabulary,
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
                                    onClick = onAddToVocabulary,
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
