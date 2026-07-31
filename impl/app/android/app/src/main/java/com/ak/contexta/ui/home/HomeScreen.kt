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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.LocalFireDepartment
import androidx.compose.material.icons.outlined.MenuBook
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.components.ArticleCard
import com.ak.contexta.ui.components.EmptyState
import com.ak.contexta.ui.components.LoadingIndicator
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.SurfaceSoft

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
                dateLabel = state.dateLabel,
                streak = state.streak
            )
        }

        // Article groups
        if (state.isGenerating) {
            item {
                EmptyState(
                    icon = Icons.Outlined.Settings,
                    message = "文章生成中",
                    subMessage = state.generationMessage.ifEmpty { "首次生成需要一些时间，请稍候…" }
                )
            }
        } else if (state.articleGroups.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Outlined.MenuBook,
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
            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun HomeHeader(
    dateLabel: String,
    streak: Int
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 20.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = dateLabel,
            style = MaterialTheme.typography.titleMedium
        )

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
            .background(SurfaceSoft)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Outlined.LocalFireDepartment,
            contentDescription = null,
            tint = Primary,
            modifier = Modifier.size(16.dp)
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = "连续 $streak 天",
            style = MaterialTheme.typography.labelMedium,
            color = Primary
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

    Column(modifier = Modifier.padding(horizontal = 20.dp)) {
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
                style = MaterialTheme.typography.titleMedium
            )
            Icon(
                imageVector = if (expanded) Icons.Outlined.ExpandMore else Icons.Outlined.ExpandLess,
                contentDescription = null,
                tint = Muted,
                modifier = Modifier.size(20.dp)
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
