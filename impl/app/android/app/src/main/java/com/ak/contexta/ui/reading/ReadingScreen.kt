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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
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
import com.ak.contexta.ui.theme.Ink
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.MutedSoft
import com.ak.contexta.ui.theme.OnPrimary
import com.ak.contexta.ui.theme.PhoneticStyle
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.Radius
import com.ak.contexta.ui.theme.SurfaceCard
import com.ak.contexta.ui.theme.SurfaceSoft

@Composable
fun ReadingScreen(
    articleId: Long,
    onBack: () -> Unit,
    onReviewWords: () -> Unit,
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

            // App bar
            ReadingAppBar(
                title = state.title ?: "文章",
                onBack = onBack,
                translationMode = state.translationMode,
                ttsSpeed = state.ttsSpeed,
                onToggleTtsSpeed = { viewModel.toggleTtsSpeed() },
                onPlayFullArticle = { viewModel.playFullArticle() },
                isReadCompleted = state.isReadCompleted
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
                        Spacer(modifier = Modifier.height(12.dp))
                        state.paragraphs.forEachIndexed { index, paragraph ->
                            ReadingParagraph(
                                englishText = paragraph.englishText,
                                chineseTranslation = paragraph.chineseTranslation,
                                translationMode = state.translationMode,
                                isRevealed = index in state.revealedParagraphs,
                                vocabularyWords = state.vocabularyWords,
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
            ReadingFooter(
                isReadCompleted = state.isReadCompleted,
                onMarkAsRead = { viewModel.markAsRead() },
                onBack = onBack,
                onReviewWords = onReviewWords
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
    title: String,
    onBack: () -> Unit,
    translationMode: TranslationMode,
    ttsSpeed: Float,
    onToggleTtsSpeed: () -> Unit,
    onPlayFullArticle: () -> Unit,
    isReadCompleted: Boolean
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
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.headlineMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        Spacer(modifier = Modifier.width(8.dp))
        // Read status (read-only badge; marking read moved to footer)
        if (isReadCompleted) {
            Text(
                text = "✓ 已读",
                style = MaterialTheme.typography.labelMedium,
                color = MutedSoft,
                modifier = Modifier.padding(horizontal = 4.dp)
            )
        }
        Spacer(modifier = Modifier.width(4.dp))
        // Play full article
        AppIconButton(
            icon = Icons.AutoMirrored.Outlined.VolumeUp,
            contentDescription = "朗读全文",
            onClick = onPlayFullArticle,
            tint = Primary
        )
        Spacer(modifier = Modifier.width(4.dp))
        // Speed toggle
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(6.dp))
                .background(if (ttsSpeed < 1.0f) SurfaceSoft else Primary)
                .clickable { onToggleTtsSpeed() }
                .padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Text(
                text = if (ttsSpeed < 1.0f) "0.5x" else "1x",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = if (ttsSpeed < 1.0f) MutedSoft else OnPrimary
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
            color = MutedSoft
        )
        Spacer(modifier = Modifier.width(8.dp))
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(SurfaceCard)
                .clickable { onCycle() }
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = mode.label,
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

@Composable
private fun ReadingParagraph(
    englishText: String,
    chineseTranslation: String,
    translationMode: TranslationMode,
    isRevealed: Boolean = false,
    vocabularyWords: Set<String> = emptySet(),
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
            }
            BasicText(
                text = annotatedString,
                style = MaterialTheme.typography.bodyLarge.copy(color = Ink, lineHeight = 27.sp),
                modifier = Modifier.weight(1f).padding(end = 8.dp)
            )

            // Play icon
            AppIconButton(
                icon = Icons.AutoMirrored.Outlined.VolumeUp,
                contentDescription = "朗读本段",
                onClick = onPlay,
                size = 36,
                tint = Primary
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
private fun ReadingFooter(
    isReadCompleted: Boolean,
    onMarkAsRead: () -> Unit,
    onBack: () -> Unit,
    onReviewWords: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (!isReadCompleted) {
            AppButton(
                text = "标记已读",
                onClick = onMarkAsRead,
                modifier = Modifier.fillMaxWidth(),
                variant = AppButtonVariant.Secondary
            )
        }
        AppButton(
            text = "复习单词",
            onClick = onReviewWords,
            modifier = Modifier.fillMaxWidth()
        )
        Text(
            text = "← 返回列表",
            style = MaterialTheme.typography.titleSmall,
            color = Primary,
            modifier = Modifier.align(Alignment.CenterHorizontally).clickable { onBack() }.padding(8.dp)
        )
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
    AppModal(visible = visible, onDismiss = onDismiss) {
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

        // Word header: 30sp serif + phonetic coral + speaker
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = data.word,
                style = MaterialTheme.typography.headlineLarge.copy(fontSize = 30.sp)
            )
            if (data.phonetic != null && !data.isLoading) {
                Spacer(modifier = Modifier.width(10.dp))
                Text(
                    text = data.phonetic,
                    style = PhoneticStyle.copy(fontSize = 15.sp),
                    modifier = Modifier.padding(bottom = 4.dp)
                )
            }
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

        // Translation (Chinese)
        if (data.translation != null) {
            Spacer(modifier = Modifier.height(12.dp))
            Text(text = data.translation, style = MaterialTheme.typography.headlineMedium, color = Ink)
        }

        // Definitions
        if (data.definitions.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                data.definitions.forEach { def ->
                    Text(text = def, style = MaterialTheme.typography.bodyMedium, color = BodyText)
                }
            }
        }

        // Example block (SurfaceSoft)
        if (data.exampleEn != null) {
            Spacer(modifier = Modifier.height(12.dp))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radius.Sm))
                    .background(SurfaceSoft)
                    .padding(12.dp)
            ) {
                Text(text = data.exampleEn, style = MaterialTheme.typography.bodyMedium, color = Ink)
                if (data.exampleZh != null) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(text = data.exampleZh, style = MaterialTheme.typography.bodyMedium, color = MutedSoft)
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
