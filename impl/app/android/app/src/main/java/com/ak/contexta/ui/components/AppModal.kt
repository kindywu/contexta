package com.ak.contexta.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Radius
import com.ak.contexta.ui.theme.Scrim

/** Centered modal per prototype: canvas bg, 16dp radius, scrim rgba(24,23,21,0.35), X close. */
@Composable
fun AppModal(
    visible: Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    AnimatedVisibility(visible = visible, enter = fadeIn(), exit = fadeOut()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Scrim)
                .clickable { onDismiss() }
        ) {
            // 内层 Column 必须消费点击（无涟漪 indication = null），
            // 否则点击卡片空白区会穿透到外层 scrim 误触发 onDismiss
            Column(
                modifier = modifier
                    .align(Alignment.Center)
                    .fillMaxWidth()
                    .widthIn(max = 360.dp)
                    .clip(RoundedCornerShape(Radius.Lg))
                    .background(Background)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = {}
                    )
                    .padding(24.dp)
            ) {
                content()
            }
        }
    }
}

/** Prototype toast: dark #181715 bg, cream text, 8dp radius. */
@Composable
fun AppToast(
    text: String,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(com.ak.contexta.ui.theme.ToastDark)
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        Text(text = text, style = MaterialTheme.typography.bodyMedium, color = com.ak.contexta.ui.theme.Background)
    }
}
