package com.ak.contexta.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.unit.dp
import com.ak.contexta.ui.theme.Accent
import com.ak.contexta.ui.theme.Meta

enum class BottomNavTab(val label: String) {
    Home("首页"),
    Vocabulary("生词"),
    Reference("参考"),
    Settings("设置")
}

@Composable
fun BottomNavBar(
    selectedTab: BottomNavTab,
    onTabSelected: (BottomNavTab) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        BottomNavTab.entries.forEach { tab ->
            val isSelected = tab == selectedTab
            val color = if (isSelected) Accent else Meta

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .clickable { onTabSelected(tab) }
                    .padding(horizontal = 16.dp)
            ) {
                Text(
                    text = when (tab) {
                        BottomNavTab.Home -> "🏠"
                        BottomNavTab.Vocabulary -> "📖"
                        BottomNavTab.Reference -> "📚"
                        BottomNavTab.Settings -> "⚙️"
                    },
                    style = MaterialTheme.typography.titleSmall,
                    color = color
                )
                Text(
                    text = tab.label,
                    style = MaterialTheme.typography.labelSmall,
                    color = color
                )
            }
        }
    }
}
