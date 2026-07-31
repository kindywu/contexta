package com.ak.contexta.ui.reading

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.components.AppButton
import com.ak.contexta.ui.components.AppButtonVariant
import com.ak.contexta.ui.components.AppIconButton
import com.ak.contexta.ui.components.AppModal
import com.ak.contexta.ui.components.EmptyState
import com.ak.contexta.ui.components.LoadingIndicator
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.BodyText
import com.ak.contexta.ui.theme.Hairline
import com.ak.contexta.ui.theme.Ink
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.MutedSoft
import com.ak.contexta.ui.theme.OnPrimary
import com.ak.contexta.ui.theme.PhoneticStyle
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.SurfaceCard
import com.ak.contexta.ui.theme.SurfaceSoft

@Composable
fun ReadingScreen(
    articleId: Long,
    onBack: () -> Unit,
    viewModel: ReadingViewModel = hiltViewModel()
) {
    val snackbarHostState = remember { SnackbarHostState() }

    val scrollState = rememberScrollState()
    val scrollFraction = remember {
        derivedStateOf {
            val max = scrollState.maxValue
            if (max > 0) scrollState.value.toFloat() / max.toFloat() else 0f
        }
    }

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
            // 3dp coral reading progress bar
            Box(
                modifier = Modifier
                    .fillMaxWidth(scrollFraction.value)
                    .height(3.dp)
                    .background(Primary)
            )

            // App bar: back + read status + translation mode (title lives in content)
            ReadingAppBar(
                onBack = onBack,
                translationMode = state.translationMode,
                isReadCompleted = state.isReadCompleted,
                onCycleTranslationMode = { viewModel.cycleTranslationMode() }
            )

            // Content
            when {
                state.isLoading -> LoadingIndicator()
                state.error != null -> EmptyState(
                    icon = Icons.Outlined.ErrorOutline,
                    message = state.error!!,
                    subMessage = "请返回重新选择"
                )
                else -> {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(scrollState)
                            .padding(horizontal = 20.dp)
                    ) {
                        // Article title at the top of the content — serif, larger than body
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = state.title ?: "文章",
                            style = MaterialTheme.typography.displayMedium.copy(color = Ink)
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(1.dp)
                                .background(Hairline)
                        )
                        Spacer(modifier = Modifier.height(20.dp))
                        state.paragraphs.forEachIndexed { index, paragraph ->
                            ReadingParagraph(
                                englishText = paragraph.englishText,
                                chineseTranslation = paragraph.chineseTranslation,
                                translationMode = state.translationMode,
                                isRevealed = index in state.revealedParagraphs,
                                vocabularyWords = state.vocabularyWords,
                                isSpeaking = state.speakingParagraphIndex == index,
                                onWordClick = { word -> viewModel.showWordSheet(word) },
                                onTranslationClick = {
                                    if (state.translationMode == TranslationMode.BLURRED) {
                                        viewModel.revealTranslation(index)
                                    }
                                },
                                onPlay = { viewModel.playParagraph(index) }
                            )
                        }
                        Spacer(modifier = Modifier.height(24.dp))
                        // Mark-as-read at the end of the article content (follows scroll)
                        if (!state.isReadCompleted) {
                            AppButton(
                                text = "标记已读",
                                onClick = { viewModel.markAsRead() },
                                modifier = Modifier.fillMaxWidth(),
                                variant = AppButtonVariant.Secondary
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                        }
                    }
                }
            }

            // Bottom player bar (always visible, music-player style)
            ReadingPlayerBar(
                isSpeaking = state.isSpeakingFullArticle,
                ttsSpeed = state.ttsSpeed,
                onTogglePlayback = { viewModel.toggleFullArticlePlayback() },
                onToggleTtsSpeed = { viewModel.toggleTtsSpeed() }
            )
        }

        // Word modal overlay (centered)
        WordModalOverlay(
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
    onBack: () -> Unit,
    translationMode: TranslationMode,
    isReadCompleted: Boolean,
    onCycleTranslationMode: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Background)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        AppIconButton(
            icon = Icons.AutoMirrored.Outlined.ArrowBack,
            contentDescription = "返回",
            onClick = onBack,
            tint = MutedSoft
        )
        // Read status (read-only badge; marking read lives at the end of the content)
        if (isReadCompleted) {
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "✓ 已读",
                style = MaterialTheme.typography.labelMedium,
                color = MutedSoft,
                modifier = Modifier.padding(horizontal = 4.dp)
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        // Translation mode selector (moved up from the former separate bar)
        Text(
            text = "译文",
            style = MaterialTheme.typography.labelMedium,
            color = MutedSoft
        )
        Spacer(modifier = Modifier.width(8.dp))
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(SurfaceCard)
                .clickable { onCycleTranslationMode() }
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = translationMode.label,
                style = MaterialTheme.typography.labelMedium,
                color = BodyText
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "▾",
                style = MaterialTheme.typography.labelSmall,
                color = MutedSoft
            )
        }
    }
}

/** 内联播放按钮在 AnnotatedString 中的占位标记（英文正文不会出现该字符串）。 */
private const val INLINE_PLAY_PLACEHOLDER = "⟨play⟩"

@Composable
private fun ReadingParagraph(
    englishText: String,
    chineseTranslation: String,
    translationMode: TranslationMode,
    isRevealed: Boolean = false,
    vocabularyWords: Set<String> = emptySet(),
    isSpeaking: Boolean = false,
    onWordClick: (String) -> Unit,
    onTranslationClick: () -> Unit,
    onPlay: () -> Unit
) {
    Column(modifier = Modifier.padding(bottom = 20.dp)) {
        // English text with clickable words + inline play icon at the end of the last line
        val annotatedString = buildAnnotatedString {
            val words = englishText.split(Regex("(?<=\\s)|(?=\\s)"))
            words.forEach { token ->
                val isWord = token.matches(Regex("[A-Za-z'-]+"))
                if (isWord) {
                    val normalized = token.lowercase()
                    val isVocab = normalized in vocabularyWords
                    val link = LinkAnnotation.Clickable(
                        tag = "word",
                        styles = TextLinkStyles(style = SpanStyle(color = Ink))
                    ) { onWordClick(normalized) }
                    withLink(link) {
                        withStyle(
                            if (isVocab) SpanStyle(color = Ink, background = Color(0x2ECC785C))
                            else SpanStyle(color = Ink)
                        ) { append(token) }
                    }
                } else {
                    append(token)
                }
            }
            // 不换行空格（U+00A0）：图标与最后一个单词整体换行，不单独甩到下一行
            append(" ")
            appendInlineContent(INLINE_PLAY_PLACEHOLDER, "🔊")
        }
        BasicText(
            text = annotatedString,
            style = MaterialTheme.typography.bodyLarge.copy(color = Ink, lineHeight = 27.sp),
            modifier = Modifier.fillMaxWidth(),
            inlineContent = mapOf(
                INLINE_PLAY_PLACEHOLDER to InlineTextContent(
                    placeholder = Placeholder(
                        width = 18.sp,
                        height = 18.sp,
                        placeholderVerticalAlign = PlaceholderVerticalAlign.Center
                    )
                ) {
                    Box(
                        modifier = Modifier.clickable(onClick = onPlay),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = if (isSpeaking) Icons.Outlined.Stop
                            else Icons.AutoMirrored.Outlined.VolumeUp,
                            contentDescription = if (isSpeaking) "停止朗读" else "朗读本段",
                            tint = if (isSpeaking) Primary else MutedSoft,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            )
        )

        Spacer(modifier = Modifier.height(4.dp))

        // Chinese translation
        val translationModifier = Modifier.padding(bottom = 4.dp)
        when (translationMode) {
            TranslationMode.FULL -> {
                Text(
                    text = chineseTranslation,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MutedSoft,
                    modifier = translationModifier
                )
            }
            TranslationMode.BLURRED -> {
                if (isRevealed) {
                    Text(
                        text = chineseTranslation,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MutedSoft,
                        modifier = translationModifier.clickable { onTranslationClick() }
                    )
                } else {
                    Text(
                        text = chineseTranslation,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MutedSoft,
                        modifier = translationModifier.then(
                            Modifier.blur(radius = 4.dp)
                        ).clickable { onTranslationClick() }
                    )
                }
            }
            TranslationMode.DIM -> {
                Text(
                    text = chineseTranslation,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MutedSoft,
                    modifier = translationModifier.graphicsLayer(alpha = 0.55f)
                )
            }
            TranslationMode.HIDDEN -> {
                // Hidden: don't show
            }
        }
    }
}

@Composable
private fun ReadingPlayerBar(
    isSpeaking: Boolean,
    ttsSpeed: Float,
    onTogglePlayback: () -> Unit,
    onToggleTtsSpeed: () -> Unit
) {
    // Music-player style bar: circular play/stop + label + speed chip. Always visible.
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(SurfaceCard)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Circular play/stop button
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(Primary)
                .clickable { onTogglePlayback() },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = if (isSpeaking) Icons.Outlined.Stop else Icons.Outlined.PlayArrow,
                contentDescription = if (isSpeaking) "停止朗读" else "朗读全文",
                tint = OnPrimary,
                modifier = Modifier.size(24.dp)
            )
        }
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = if (isSpeaking) "正在朗读…" else "朗读全文",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = if (isSpeaking) Primary else BodyText
        )
        Spacer(modifier = Modifier.weight(1f))
        // Speed toggle
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(6.dp))
                .background(if (ttsSpeed < 1.0f) SurfaceSoft else Primary)
                .clickable { onToggleTtsSpeed() }
                .padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Text(
                text = if (ttsSpeed < 1.0f) "0.75x" else "1x",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = if (ttsSpeed < 1.0f) MutedSoft else OnPrimary
            )
        }
    }
}

@Composable
private fun WordModalOverlay(
    visible: Boolean,
    data: WordSheetData?,
    onDismiss: () -> Unit,
    onAddToVocabulary: () -> Unit,
    onRemoveFromVocabulary: () -> Unit,
    onPlayWord: () -> Unit
) {
    AppModal(visible = visible, onDismiss = onDismiss, alignment = Alignment.BottomCenter) {
        // Close X — top right
        Box(modifier = Modifier.fillMaxWidth()) {
            AppIconButton(
                icon = Icons.Outlined.Close,
                contentDescription = "关闭",
                onClick = onDismiss,
                modifier = Modifier.align(Alignment.TopEnd),
                size = 32,
                tint = MutedSoft
            )
        }

        if (data == null) return@AppModal

        // Word header: 26sp serif + speaker; phonetic on its own wrapping line below
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = data.word,
                style = MaterialTheme.typography.headlineLarge.copy(fontSize = 26.sp)
            )
            Spacer(modifier = Modifier.weight(1f))
            if (!data.isLoading) {
                AppIconButton(
                    icon = Icons.AutoMirrored.Outlined.VolumeUp,
                    contentDescription = "发音",
                    onClick = onPlayWord,
                    size = 36,
                    tint = Primary
                )
            }
        }
        if (data.phonetic != null && !data.isLoading) {
            Text(
                text = data.phonetic,
                style = PhoneticStyle.copy(fontSize = 13.sp)
            )
        }

        // Loading state
        if (data.isLoading) {
            Spacer(modifier = Modifier.height(20.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = Primary)
                Spacer(modifier = Modifier.width(12.dp))
                Text(text = "正在查询…", style = MaterialTheme.typography.bodyMedium, color = Muted)
            }
            Spacer(modifier = Modifier.height(20.dp))
            return@AppModal
        }

        // Senses grouped by part of speech: POS label (coral) → English definition → Chinese meaning.
        // Same-POS senses are adjacent (grouped in ViewModel); label only on the first item of a group.
        // Scrollable so the action button stays pinned while content exceeds the sheet height.
        if (data.senses.isNotEmpty()) {
            Spacer(modifier = Modifier.height(12.dp))
            Column(
                modifier = Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
            ) {
                data.senses.forEachIndexed { index, sense ->
                    val isNewGroup =
                        index == 0 || sense.partOfSpeech != data.senses[index - 1].partOfSpeech
                    if (isNewGroup) {
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            text = sense.partOfSpeech,
                            style = MaterialTheme.typography.labelMedium,
                            color = Primary
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                    } else {
                        Spacer(modifier = Modifier.height(8.dp))
                    }
                    Text(
                        text = sense.englishDefinition,
                        style = MaterialTheme.typography.bodySmall,
                        color = Ink
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = sense.chineseMeaning,
                        style = MaterialTheme.typography.bodySmall,
                        color = MutedSoft
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(20.dp))

        // Full-width action button (secondary style when already in vocabulary)
        if (data.isInVocabulary) {
            AppButton(
                text = "从生词表移除",
                onClick = onRemoveFromVocabulary,
                modifier = Modifier.fillMaxWidth(),
                variant = AppButtonVariant.Secondary
            )
        } else {
            AppButton(
                text = "加入生词表",
                onClick = onAddToVocabulary,
                modifier = Modifier.fillMaxWidth()
            )
        }

        Spacer(modifier = Modifier.height(4.dp))
    }
}
