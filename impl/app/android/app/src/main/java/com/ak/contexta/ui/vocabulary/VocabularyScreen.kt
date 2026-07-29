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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
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
fun VocabularyScreen(
    viewModel: VocabularyViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        // Header
        VocabularyHeader(totalCount = state.totalCount)

        if (state.isLoading) {
            LoadingIndicator()
        } else if (state.totalCount == 0) {
            EmptyState(
                icon = "📝",
                message = "生词表为空",
                subMessage = "阅读时点击单词可加入生词表"
            )
        } else {
            // Progress bar
            VocabularyProgress(
                current = state.currentIndex + 1,
                total = state.totalCount
            )

            // Word card
            val word = state.currentWord
            if (word != null) {
                VocabularyCard(
                    word = word.word,
                    phonetic = word.phonetic,
                    translation = word.translation,
                    definitions = word.definitions,
                    exampleEn = word.exampleEn,
                    exampleZh = word.exampleZh,
                    reviewStreak = word.reviewStreak,
                    masteryThreshold = word.masteryThreshold
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

@Composable
private fun VocabularyHeader(totalCount: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Surface)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "生词复习",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = "$totalCount 个词",
            style = MaterialTheme.typography.labelMedium,
            color = Muted
        )
    }
}

@Composable
private fun VocabularyProgress(current: Int, total: Int) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Text(
            text = "$current / $total",
            style = MaterialTheme.typography.labelMedium,
            color = Muted
        )
        Spacer(modifier = Modifier.height(6.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(SurfaceWarm)
        ) {
            val progress = if (total > 0) current.toFloat() / total else 0f
            Box(
                modifier = Modifier
                    .fillMaxWidth(progress)
                    .height(6.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(Accent)
            )
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
    masteryThreshold: Int
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Surface)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Word
        Text(
            text = word,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        if (phonetic != null) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = phonetic,
                style = MaterialTheme.typography.bodyLarge,
                color = Meta
            )
        }

        // Play button
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "🔊",
            style = MaterialTheme.typography.titleMedium,
            color = Accent,
            modifier = Modifier.clickable { /* TTS placeholder */ }
        )

        // Translation
        if (translation != null) {
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = translation,
                style = MaterialTheme.typography.titleMedium,
                color = ForegroundSecondary
            )
        }

        // Definitions
        if (definitions.isNotEmpty()) {
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = definitions.joinToString("; "),
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        }

        // Example
        if (exampleEn != null) {
            Spacer(modifier = Modifier.height(12.dp))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(Background)
                    .padding(12.dp)
            ) {
                Text(
                    text = exampleEn,
                    style = MaterialTheme.typography.bodySmall,
                    color = Foreground
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
            style = MaterialTheme.typography.labelSmall,
            color = Meta
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
        Button(
            onClick = onIncorrect,
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = SurfaceWarm,
                contentColor = Foreground
            )
        ) {
            Text("✗ 不认识")
        }

        Button(
            onClick = onCorrect,
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Accent,
                contentColor = AccentOn
            )
        ) {
            Text("✓ 认识了")
        }
    }
}
