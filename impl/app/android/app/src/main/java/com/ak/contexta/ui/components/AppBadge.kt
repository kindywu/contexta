package com.ak.contexta.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.OnPrimary
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.Radius
import com.ak.contexta.ui.theme.Success
import com.ak.contexta.ui.theme.SurfaceSoft

enum class AppBadgeVariant { Default, Coral, Green }

/** Small pill badge: difficulty labels, counters. */
@Composable
fun AppBadge(
    text: String,
    variant: AppBadgeVariant = AppBadgeVariant.Default,
    modifier: Modifier = Modifier
) {
    val (bg, fg) = when (variant) {
        AppBadgeVariant.Coral -> Primary to OnPrimary
        AppBadgeVariant.Green -> Success to OnPrimary
        AppBadgeVariant.Default -> SurfaceSoft to Muted
    }
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = fg,
        modifier = modifier
            .clip(RoundedCornerShape(Radius.Pill))
            .background(bg)
            .padding(horizontal = 8.dp, vertical = 2.dp)
    )
}
