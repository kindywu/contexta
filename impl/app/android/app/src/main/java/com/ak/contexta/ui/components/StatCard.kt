package com.ak.contexta.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.ak.contexta.ui.theme.Primary

data class StatCardData(
    val number: String,
    val label: String,
    val sub: String? = null
)

@Composable
fun StatCard(
    stat: StatCardData,
    modifier: Modifier = Modifier
) {
    AppCard(modifier = modifier.fillMaxWidth()) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = stat.number,
                style = MaterialTheme.typography.headlineMedium
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = stat.label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (stat.sub != null) {
                Text(
                    text = stat.sub,
                    style = MaterialTheme.typography.labelSmall,
                    color = Primary
                )
            }
        }
    }
}
