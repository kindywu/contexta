package com.ak.contexta.ui.home

import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.components.ArticleCard
import com.ak.contexta.ui.components.EmptyState
import com.ak.contexta.ui.components.LoadingIndicator
import com.ak.contexta.ui.theme.Accent
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Foreground
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.SurfaceWarm

@Composable
fun HomeScreen(
    onArticleClick: (Long) -> Unit,
    viewModel: HomeViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    if (state.isLoading) {
        LoadingIndicator()
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        // Header
        item {
            HomeHeader(
                greeting = state.greeting,
                dateLabel = state.dateLabel,
                streak = state.streak
            )
        }

        // Article groups
        if (state.isGenerating) {
            item {
                EmptyState(
                    icon = "⚙️",
                    message = "文章生成中",
                    subMessage = state.generationMessage.ifEmpty { "首次生成需要一些时间，请稍候…" }
                )
            }
        } else if (state.articleGroups.isEmpty()) {
            item {
                EmptyState(
                    icon = "📖",
                    message = "暂无文章",
                    subMessage = "请等待文章生成"
                )
            }
        } else {
            state.articleGroups.forEach { group ->
                item {
                    DayGroup(
                        dateLabel = group.dateLabel,
                        articles = group.articles,
                        onArticleClick = onArticleClick
                    )
                }
            }
        }

        // Bottom spacer for nav bar
        item {
            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun HomeHeader(
    greeting: String,
    dateLabel: String,
    streak: Int
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Top
    ) {
        Column {
            Text(
                text = greeting,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = dateLabel,
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        }

        if (streak > 0) {
            StreakBadge(streak = streak)
        }
    }
}

@Composable
private fun StreakBadge(streak: Int) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(SurfaceWarm)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = "🔥", style = MaterialTheme.typography.bodyMedium)
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = "连续 $streak 天",
            style = MaterialTheme.typography.labelMedium,
            color = Accent
        )
    }
}



@Composable
private fun DayGroup(
    dateLabel: String,
    articles: List<ArticleItemUi>,
    onArticleClick: (Long) -> Unit
) {
    var expanded by remember { mutableStateOf(true) }

    Column(modifier = Modifier.padding(horizontal = 16.dp)) {
        // Day header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = dateLabel,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = if (expanded) "▾" else "▸",
                style = MaterialTheme.typography.titleSmall,
                color = Muted
            )
        }

        AnimatedVisibility(visible = expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                articles.forEach { article ->
                    ArticleCard(
                        article = com.ak.contexta.ui.components.ArticleCardData(
                            id = article.id,
                            title = article.title,
                            description = article.description,
                            difficultyLabel = article.difficultyLabel,
                            categoryLabel = article.categoryLabel,
                            isReadCompleted = article.isReadCompleted
                        ),
                        onClick = { onArticleClick(article.id) }
                    )
                }
            }
        }
    }

    Spacer(modifier = Modifier.height(8.dp))
}
