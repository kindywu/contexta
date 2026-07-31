package com.ak.contexta.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.ak.contexta.ui.theme.Radius
import com.ak.contexta.ui.theme.SurfaceCard

/** Prototype card: SurfaceCard bg + hairline border + 12dp radius + 16dp padding. */
@Composable
fun AppCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    val shape = RoundedCornerShape(Radius.Md)
    Box(
        modifier = modifier
            .clip(shape)
            .background(SurfaceCard)
            .then(
                if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier
            )
            .padding(16.dp)
    ) {
        // ColumnScope 类型的 content 需在 Column 作用域内调用（与 Material3 Card 一致）
        Column {
            content()
        }
    }
}
