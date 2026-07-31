package com.ak.contexta.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ak.contexta.ui.theme.Ink
import com.ak.contexta.ui.theme.OnPrimary
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.PrimaryDisabled
import com.ak.contexta.ui.theme.Radius
import com.ak.contexta.ui.theme.SurfaceCard

enum class AppButtonVariant { Primary, Secondary }

/** Prototype-style button: coral filled (primary) or hairline-outlined (secondary). */
@Composable
fun AppButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    variant: AppButtonVariant = AppButtonVariant.Primary,
    enabled: Boolean = true
) {
    val container = when {
        !enabled -> PrimaryDisabled.copy(alpha = 0.4f)
        variant == AppButtonVariant.Primary -> Primary
        else -> SurfaceCard
    }
    val contentColor = when {
        !enabled -> Ink.copy(alpha = 0.4f)
        variant == AppButtonVariant.Primary -> OnPrimary
        else -> Ink
    }
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(Radius.Sm))
            .background(container)
            .clickable(enabled = enabled) { onClick() }
            .padding(horizontal = 20.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Medium,
            color = contentColor
        )
    }
}

/** Circular icon button, 36-44dp touch target per prototype. */
@Composable
fun AppIconButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Int = 44,
    tint: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurface
) {
    IconButton(onClick = onClick, modifier = modifier.size(size.dp)) {
        Icon(imageVector = icon, contentDescription = contentDescription, tint = tint)
    }
}
