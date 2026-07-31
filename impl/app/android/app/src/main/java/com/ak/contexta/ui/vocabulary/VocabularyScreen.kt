package com.ak.contexta.ui.vocabulary

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Celebration
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.components.AppButton
import com.ak.contexta.ui.components.AppButtonVariant
import com.ak.contexta.ui.components.AppCard
import com.ak.contexta.ui.components.AppIconButton
import com.ak.contexta.ui.components.AppTopBar
import com.ak.contexta.ui.components.EmptyState
import com.ak.contexta.ui.components.LoadingIndicator
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.BodyText
import com.ak.contexta.ui.theme.Hairline
import com.ak.contexta.ui.theme.Ink
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.MutedSoft
import com.ak.contexta.ui.theme.PhoneticStyle
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.Radius
import com.ak.contexta.ui.theme.Success
import com.ak.contexta.ui.theme.SurfaceCard
import com.ak.contexta.ui.theme.SurfaceSoft
import kotlinx.coroutines.launch

@Composable
fun VocabularyScreen(
    viewModel: VocabularyViewModel = hiltViewModel(),
    onAddWord: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        // Header
        AppTopBar(
            title = if (!state.isSummary) "生词复习" else "复习总结",
            actions = {
                if (!state.isSummary) {
                    Text(
                        text = "${state.totalCount} 个词",
                        style = MaterialTheme.typography.titleSmall,
                        color = Muted,
                        modifier = Modifier.padding(end = 12.dp)
                    )
                    AppIconButton(
                        icon = Icons.Outlined.Add,
                        contentDescription = "录入单词",
                        onClick = onAddWord,
                        tint = Primary
                    )
                }
            }
        )

        when {
            state.isLoading -> LoadingIndicator()
            state.isSummary -> VocabularySummary(
                reviewedCount = state.reviewedCount,
                newlyKnownCount = state.newlyKnownCount,
                onRestart = { viewModel.restart() }
            )
            state.totalCount == 0 -> EmptyState(
                icon = Icons.Outlined.EditNote,
                message = "生词表为空",
                subMessage = "阅读时点击单词可加入生词表"
            )
            else -> {
                val word = state.currentWord
                if (word != null) {
                    // Progress dots
                    VocabularyProgressDots(
                        current = state.currentIndex + 1,
                        total = state.totalCount
                    )

                    // Word card
                    val scope = rememberCoroutineScope()
                    val offsetY = remember { Animatable(0f) }
                    // Swipe-to-switch card (prototype: vertical drag >60dp, spring back)
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .pointerInput(Unit) {
                                detectDragGestures(
                                    onDrag = { change, amount ->
                                        change.consume()
                                        scope.launch { offsetY.snapTo(offsetY.value + amount.y) }
                                    },
                                    onDragEnd = {
                                        val threshold = 60.dp.toPx()
                                        scope.launch {
                                            when {
                                                offsetY.value < -threshold -> {
                                                    offsetY.animateTo(-offsetY.value * 1.5f, tween(150))
                                                    viewModel.goNext()
                                                    offsetY.snapTo(0f)
                                                }
                                                offsetY.value > threshold -> {
                                                    viewModel.goPrevious()
                                                    offsetY.snapTo(0f)
                                                }
                                                else -> offsetY.animateTo(0f, spring(dampingRatio = Spring.DampingRatioMediumBouncy))
                                            }
                                        }
                                    }
                                )
                            }
                            .graphicsLayer { translationY = offsetY.value }
                    ) {
                        VocabularyCard(
                            word = word.word,
                            phonetic = word.phonetic,
                            translation = word.translation,
                            definitions = word.definitions,
                            exampleEn = word.exampleEn,
                            exampleZh = word.exampleZh,
                            reviewStreak = word.reviewStreak,
                            masteryThreshold = word.masteryThreshold,
                            onPlayWord = { viewModel.playWord() }
                        )
                    }

                    Spacer(modifier = Modifier.weight(1f))

                    // Action buttons
                    VocabularyActions(
                        onCorrect = { viewModel.markCorrect() },
                        onIncorrect = { viewModel.markIncorrect() }
                    )
                }
            }
        }
    }
}

@Composable
private fun VocabularySummary(
    reviewedCount: Int,
    newlyKnownCount: Int,
    onRestart: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Outlined.Celebration,
            contentDescription = null,
            tint = Success,
            modifier = Modifier.size(56.dp)
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "复习完成！",
            style = MaterialTheme.typography.headlineLarge
        )
        Spacer(modifier = Modifier.height(24.dp))

        AppCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                SummaryStat(value = reviewedCount.toString(), label = "复习单词")
                Spacer(modifier = Modifier.height(16.dp))
                SummaryStat(value = newlyKnownCount.toString(), label = "新标记认识")
            }
        }

        Spacer(modifier = Modifier.height(32.dp))

        AppButton(text = "再来一轮", onClick = onRestart)
    }
}

@Composable
private fun SummaryStat(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            style = MaterialTheme.typography.headlineMedium,
            color = Primary
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = Muted
        )
    }
}

@Composable
private fun VocabularyProgressDots(current: Int, total: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "$current / $total",
            style = MaterialTheme.typography.labelMedium,
            color = MutedSoft,
            modifier = Modifier.padding(end = 12.dp)
        )
        // dots: current = 16dp coral pill, done = muted dot, upcoming = hairline dot
        Row(modifier = Modifier.horizontalScroll(rememberScrollState())) {
            repeat(total) { index ->
                val step = index + 1
                val isCurrent = step == current
                val isDone = step < current
                Box(
                    modifier = Modifier
                        .padding(horizontal = 2.dp)
                        .height(6.dp)
                        .width(if (isCurrent) 16.dp else 6.dp)
                        .clip(if (isCurrent) RoundedCornerShape(3.dp) else CircleShape)
                        .background(
                            when {
                                isCurrent -> Primary
                                isDone -> Muted.copy(alpha = 0.4f)
                                else -> Hairline
                            }
                        )
                )
            }
        }
    }
}

@Composable
private fun VocabularyCard(
    word: String,
    phonetic: String?,
    translation: String?,
    definitions: List<String>,
    exampleEn: String?,
    exampleZh: String?,
    reviewStreak: Int,
    masteryThreshold: Int,
    onPlayWord: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .clip(RoundedCornerShape(Radius.Md))
            .background(SurfaceCard)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Word
        Text(
            text = word,
            style = MaterialTheme.typography.headlineLarge.copy(fontSize = 30.sp)
        )

        if (phonetic != null) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = phonetic,
                style = PhoneticStyle.copy(fontSize = 15.sp)
            )
        }

        // Play button
        Spacer(modifier = Modifier.height(8.dp))
        AppIconButton(
            icon = Icons.AutoMirrored.Outlined.VolumeUp,
            contentDescription = "发音",
            onClick = onPlayWord,
            size = 36,
            tint = Primary
        )

        // Translation
        if (translation != null) {
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = translation,
                style = MaterialTheme.typography.headlineMedium,
                color = Ink
            )
        }

        // Definitions
        if (definitions.isNotEmpty()) {
            Spacer(modifier = Modifier.height(12.dp))
            definitions.forEach { definition ->
                Text(
                    text = definition,
                    style = MaterialTheme.typography.bodyMedium,
                    color = BodyText
                )
            }
        }

        // Example
        if (exampleEn != null) {
            Spacer(modifier = Modifier.height(12.dp))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(SurfaceSoft)
                    .padding(12.dp)
            ) {
                Text(
                    text = exampleEn,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Ink
                )
                if (exampleZh != null) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = exampleZh,
                        style = MaterialTheme.typography.bodySmall,
                        color = Muted
                    )
                }
            }
        }

        // Review streak info
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "已认识 $reviewStreak/$masteryThreshold 次",
            style = MaterialTheme.typography.labelMedium,
            color = MutedSoft
        )
    }
}

@Composable
private fun VocabularyActions(
    onCorrect: () -> Unit,
    onIncorrect: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        AppButton(
            text = "✗ 不认识",
            onClick = onIncorrect,
            modifier = Modifier.weight(1f),
            variant = AppButtonVariant.Secondary
        )
        AppButton(
            text = "✓ 认识了",
            onClick = onCorrect,
            modifier = Modifier.weight(1f)
        )
    }
}
