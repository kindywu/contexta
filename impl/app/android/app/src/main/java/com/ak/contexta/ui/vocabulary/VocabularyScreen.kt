package com.ak.contexta.ui.vocabulary

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Celebration
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.components.AppButton
import com.ak.contexta.ui.components.AppCard
import com.ak.contexta.ui.components.AppIconButton
import com.ak.contexta.ui.components.EmptyState
import com.ak.contexta.ui.components.LoadingIndicator
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Hairline
import com.ak.contexta.ui.theme.Ink
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.MutedSoft
import com.ak.contexta.ui.theme.OnPrimary
import com.ak.contexta.ui.theme.PhoneticStyle
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.Radius
import com.ak.contexta.ui.theme.Success
import com.ak.contexta.ui.theme.SurfaceSoft

@Composable
fun VocabularyScreen(
    viewModel: VocabularyViewModel = hiltViewModel(),
    onBack: () -> Unit = {},
    onAddWord: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        // Top bar: back button + progress dots + add button
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
            Spacer(modifier = Modifier.weight(1f))
            if (!state.isSummary && state.totalCount > 0) {
                VocabularyProgressDots(
                    current = state.currentIndex + 1,
                    total = state.totalCount
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            AppIconButton(
                icon = Icons.Outlined.Add,
                contentDescription = "录入单词",
                onClick = onAddWord,
                tint = Primary
            )
        }

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
                    // Card area — scrollable content, fling at boundaries switches word
                    val scrollState = rememberScrollState()
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .nestedScroll(
                                remember(scrollState) {
                                    CardSwitchNestedScroll(scrollState) { direction ->
                                        when (direction) {
                                            -1 -> viewModel.goNext()
                                            1 -> viewModel.goPrevious()
                                        }
                                    }
                                }
                            )
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(scrollState),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            VocabularyCard(
                                word = word.word,
                                phonetic = word.phonetic,
                                senses = word.senses,
                                reviewStreak = word.reviewStreak,
                                masteryThreshold = word.masteryThreshold,
                                onPlayWord = { viewModel.playWord() }
                            )
                            // Bottom space so content clears the FAB
                            Spacer(modifier = Modifier.height(80.dp))
                        }

                        // Floating action button — bottom-end, circular
                        Box(
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .padding(20.dp)
                                .size(56.dp)
                                .clip(CircleShape)
                                .background(Primary)
                                .clickable { viewModel.markCorrect() },
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "✓",
                                style = MaterialTheme.typography.headlineSmall,
                                color = OnPrimary
                            )
                        }
                    }
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
        modifier = Modifier.padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "$current / $total",
            style = MaterialTheme.typography.labelMedium,
            color = MutedSoft,
            modifier = Modifier.padding(end = 8.dp)
        )
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

@Composable
private fun VocabularyCard(
    word: String,
    phonetic: String?,
    senses: List<VocabSenseData>,
    reviewStreak: Int,
    masteryThreshold: Int,
    onPlayWord: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Word
        Text(
            text = word,
            style = MaterialTheme.typography.headlineLarge.copy(fontSize = 38.sp)
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

        // Sense blocks — one per part of speech
        Spacer(modifier = Modifier.height(16.dp))
        senses.forEach { sense ->
            SenseBlock(
                partOfSpeech = sense.partOfSpeech,
                chineseMeaning = sense.chineseMeaning,
                englishDefinition = sense.englishDefinition,
                examples = sense.examples
            )
            Spacer(modifier = Modifier.height(12.dp))
        }

        // Review streak info
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "已认识 $reviewStreak/$masteryThreshold 次",
            style = MaterialTheme.typography.labelMedium,
            color = MutedSoft
        )
    }
}

@Composable
private fun SenseBlock(
    partOfSpeech: String,
    chineseMeaning: String,
    englishDefinition: String,
    examples: List<VocabExampleData>
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.Sm))
            .background(SurfaceSoft)
            .padding(12.dp)
    ) {
        // POS label + Chinese meaning on same row
        Row(verticalAlignment = Alignment.Top) {
            Text(
                text = partOfSpeech,
                style = MaterialTheme.typography.labelLarge,
                color = Primary
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = chineseMeaning,
                style = MaterialTheme.typography.headlineSmall,
                color = Ink
            )
        }

        // English definition
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = englishDefinition,
            style = MaterialTheme.typography.bodySmall,
            color = Muted
        )

        // Examples — titled section inside the same box as the translation
        if (examples.isNotEmpty()) {
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = "example",
                style = MaterialTheme.typography.labelLarge,
                color = Primary
            )
            examples.forEach { example ->
                Spacer(modifier = Modifier.height(4.dp))
                Column {
                    Text(
                        text = example.sentenceEn,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Ink
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = example.sentenceZh,
                        style = MaterialTheme.typography.bodySmall,
                        color = Muted
                    )
                }
            }
        }
    }
}

/**
 * Nested scroll connection that switches cards when the user flings past
 * the scroll boundary. Content scrolls normally within bounds; a fling
 * at the top or bottom edge triggers card switch.
 */
private class CardSwitchNestedScroll(
    private val scrollState: androidx.compose.foundation.ScrollState,
    private val onSwitch: (direction: Int) -> Unit // -1 = next, +1 = previous
) : androidx.compose.ui.input.nestedscroll.NestedScrollConnection {

    override suspend fun onPostFling(
        consumed: androidx.compose.ui.unit.Velocity,
        available: androidx.compose.ui.unit.Velocity
    ): androidx.compose.ui.unit.Velocity {
        if (available.y < -500f) {
            // Fling past bottom → next word
            onSwitch(-1)
        } else if (available.y > 500f) {
            // Fling past top → previous word
            onSwitch(1)
        }
        return androidx.compose.ui.unit.Velocity.Zero
    }
}
