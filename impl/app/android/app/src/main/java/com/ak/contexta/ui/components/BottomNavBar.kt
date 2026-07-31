package com.ak.contexta.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoStories
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.MenuBook
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.ak.contexta.navigation.Screen
import com.ak.contexta.ui.theme.Hairline
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.Primary

enum class BottomNavTab(val route: String, val label: String, val icon: ImageVector) {
    Home(Screen.Home.route, "首页", Icons.Outlined.Home),
    Vocabulary(Screen.Vocabulary.route, "生词", Icons.Outlined.MenuBook),
    Reference(Screen.Reference.route, "参考", Icons.Outlined.AutoStories),
    Settings(Screen.Settings.route, "设置", Icons.Outlined.Settings)
}

@Composable
fun BottomNavBar(
    selectedTab: BottomNavTab,
    onTabSelected: (BottomNavTab) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth()) {
        // 1px hairline top border
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(Hairline)
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .heightIn(min = 44.dp)
                .padding(vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            BottomNavTab.entries.forEach { tab ->
                val isSelected = tab == selectedTab
                val color = if (isSelected) Primary else Muted
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier
                        .clickable { onTabSelected(tab) }
                        .padding(horizontal = 16.dp)
                ) {
                    Icon(
                        imageVector = tab.icon,
                        contentDescription = tab.label,
                        tint = color,
                        modifier = Modifier.height(24.dp)
                    )
                    Text(
                        text = tab.label,
                        style = MaterialTheme.typography.titleSmall,
                        color = color
                    )
                }
            }
        }
    }
}
