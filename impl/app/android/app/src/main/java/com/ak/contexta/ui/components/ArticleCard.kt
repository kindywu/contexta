package com.ak.contexta.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.MutedSoft

data class ArticleCardData(
    val id: Long,
    val title: String?,
    val description: String,
    val difficultyLabel: String,
    val categoryLabel: String,
    val isReadCompleted: Boolean = false
)

@Composable
fun ArticleCard(
    article: ArticleCardData,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    AppCard(
        onClick = onClick,
        modifier = modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = article.title ?: article.description.take(40),
                style = MaterialTheme.typography.headlineMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = article.description,
                style = MaterialTheme.typography.bodyMedium,
                color = Muted,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                AppBadge(
                    text = article.difficultyLabel,
                    variant = when (article.difficultyLabel) {
                        "CET4" -> AppBadgeVariant.Coral
                        "CET6" -> AppBadgeVariant.Green
                        else -> AppBadgeVariant.Default
                    }
                )
                Text(
                    text = article.categoryLabel,
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted
                )
                if (article.isReadCompleted) {
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        text = "✓ 已读",
                        style = MaterialTheme.typography.labelSmall,
                        color = MutedSoft
                    )
                }
            }
        }
    }
}
