package com.ak.contexta.ui.settings

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.components.AppTopBar
import com.ak.contexta.ui.components.LoadingIndicator
import com.ak.contexta.ui.components.SectionLabel
import com.ak.contexta.ui.components.StatCard
import com.ak.contexta.ui.components.StatCardData
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Ink
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.MutedSoft
import com.ak.contexta.ui.theme.OnPrimary
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.SurfaceCard
import com.ak.contexta.ui.theme.SurfaceSoft

@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showLevelPicker by remember { mutableStateOf(false) }
    var showTranslationModePicker by remember { mutableStateOf(false) }

    if (state.isLoading) {
        LoadingIndicator()
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        AppTopBar(title = "设置")

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
        ) {
            Spacer(modifier = Modifier.height(8.dp))

            // Learning settings section
            SectionLabel(title = "学习设置")

            // Level picker
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                SettingsPickerItem(
                    label = "英文水平",
                    description = levelDescription(state.level),
                    value = levelLabel(state.level),
                    onClick = { showLevelPicker = true },
                    modifier = Modifier.weight(1f)
                )
                InfoTipButton(onClick = { viewModel.showLevelInfo() })
            }

            // Daily count stepper
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                SettingsStepperItem(
                    label = "每日文章数量",
                    description = "从CURRENT batch中展示的文章数，最多5篇",
                    value = state.dailyCount,
                    canDecrement = state.dailyCount > 1,
                    canIncrement = state.dailyCount < 5,
                    onDecrement = { viewModel.requestCountChange(state.dailyCount - 1) },
                    onIncrement = { viewModel.requestCountChange(state.dailyCount + 1) },
                    modifier = Modifier.weight(1f)
                )
                InfoTipButton(onClick = { viewModel.showCountInfo() })
            }

            // Translation mode picker
            SettingsPickerItem(
                label = "译文默认模式",
                description = "文章阅读时译文显示方式",
                value = translationModeLabel(state.translationMode),
                onClick = { showTranslationModePicker = true }
            )

            // Mastery threshold stepper
            SettingsStepperItem(
                label = "单词掌握阈值",
                description = "标记认识 N 次后自动移除",
                value = state.masteryThreshold,
                canDecrement = state.masteryThreshold > 1,
                canIncrement = state.masteryThreshold < 5,
                onDecrement = { viewModel.decrementMasteryThreshold() },
                onIncrement = { viewModel.incrementMasteryThreshold() }
            )

            // Auto play TTS toggle
            SettingsToggleItem(
                label = "自动朗读",
                description = "进入文章后自动播放朗读",
                checked = state.autoPlayAudio,
                onToggle = { viewModel.toggleAutoPlayAudio() }
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Stats section
            SectionLabel(title = "学习统计")

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                StatCard(
                    stat = StatCardData(
                        number = state.stats.totalArticlesRead.toString(),
                        label = "阅读文章"
                    ),
                    modifier = Modifier.weight(1f)
                )
                StatCard(
                    stat = StatCardData(
                        number = state.stats.totalWordsAdded.toString(),
                        label = "添加单词"
                    ),
                    modifier = Modifier.weight(1f)
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                StatCard(
                    stat = StatCardData(
                        number = state.stats.totalLearningDays.toString(),
                        label = "累计学习天数"
                    ),
                    modifier = Modifier.weight(1f)
                )
                StatCard(
                    stat = StatCardData(
                        number = state.stats.currentStreak.toString(),
                        label = "当前连续学习"
                    ),
                    modifier = Modifier.weight(1f)
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            // About section
            SectionLabel(title = "关于")

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "版本",
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = "Contexta 1.0.0",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MutedSoft
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    // Level picker dialog
    if (showLevelPicker) {
        SettingsPickerDialog(
            title = "选择英文水平",
            options = listOf(
                "LOW" to "初级",
                "MEDIUM" to "中级",
                "HIGH" to "高级"
            ),
            selectedValue = state.level,
            onSelect = { level ->
                viewModel.requestLevelChange(level)
                showLevelPicker = false
            },
            onDismiss = { showLevelPicker = false }
        )
    }

    // Translation mode picker dialog
    if (showTranslationModePicker) {
        SettingsPickerDialog(
            title = "选择译文默认模式",
            options = listOf(
                "FULL" to "完全显示",
                "DIM" to "淡化",
                "BLURRED" to "模糊",
                "HIDDEN" to "隐藏"
            ),
            selectedValue = state.translationMode,
            onSelect = { mode ->
                viewModel.updateTranslationMode(mode)
                showTranslationModePicker = false
            },
            onDismiss = { showTranslationModePicker = false }
        )
    }

    // ── ℹ️ Info dialogs ──

    // Level info dialog
    if (state.showLevelInfoDialog) {
        SettingsInfoDialog(
            title = "英文水平",
            message = "难度和篇数的修改将在第二天自动生效，不会影响今天的学习。",
            onConfirm = { viewModel.dismissInfoDialog() }
        )
    }

    // Count info dialog
    if (state.showCountInfoDialog) {
        SettingsInfoDialog(
            title = "每日文章数量",
            message = "难度和篇数的修改将在第二天自动生效，不会影响今天的学习。",
            onConfirm = { viewModel.dismissInfoDialog() }
        )
    }

    // ── Confirmation dialogs ──

    // Level change confirmation
    if (state.showLevelConfirmDialog) {
        SettingsConfirmDialog(
            title = "修改英文水平",
            message = "此设置将在明天生效，今天的学习不受影响。",
            confirmLabel = "确认修改",
            onConfirm = { viewModel.confirmLevelChange() },
            onDismiss = { viewModel.cancelLevelChange() }
        )
    }

    // Count change confirmation
    if (state.showCountConfirmDialog) {
        val pendingCount = state.pendingCount ?: state.dailyCount
        SettingsConfirmDialog(
            title = "修改每日文章数量",
            message = "当前：${state.dailyCount}篇 → 调整至：${pendingCount}篇\n\n此设置将在明天生效，今天的学习不受影响。",
            confirmLabel = "确认修改",
            onConfirm = { viewModel.confirmCountChange() },
            onDismiss = { viewModel.cancelCountChange() }
        )
    }
}

@Composable
private fun SettingsPickerDialog(
    title: String,
    options: List<Pair<String, String>>,
    selectedValue: String,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = title,
                style = MaterialTheme.typography.headlineMedium
            )
        },
        text = {
            Column {
                options.forEach { (value, label) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(value) }
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = value == selectedValue,
                            onClick = { onSelect(value) },
                            colors = RadioButtonDefaults.colors(
                                selectedColor = Primary,
                                unselectedColor = MutedSoft
                            )
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = label,
                            style = MaterialTheme.typography.bodyLarge,
                            color = Ink
                        )
                    }
                }
            }
        },
        confirmButton = {},
        containerColor = SurfaceCard,
        titleContentColor = Ink
    )
}

@Composable
private fun SettingsPickerItem(
    label: String,
    description: String,
    value: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clickable { onClick() }
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.titleMedium,
                color = Ink
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                color = Muted
            )
            Icon(
                imageVector = Icons.Outlined.ChevronRight,
                contentDescription = null,
                tint = MutedSoft,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
private fun SettingsStepperItem(
    label: String,
    description: String,
    value: Int,
    canDecrement: Boolean,
    canIncrement: Boolean,
    onDecrement: () -> Unit,
    onIncrement: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.titleMedium,
                color = Ink
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(if (canDecrement) SurfaceCard else SurfaceSoft.copy(alpha = 0.3f))
                    .clickable(enabled = canDecrement) { onDecrement() }
                    .padding(0.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "−",
                    style = MaterialTheme.typography.titleMedium,
                    color = if (canDecrement) Ink else MutedSoft.copy(alpha = 0.3f)
                )
            }
            Text(
                text = value.toString(),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.width(24.dp),
                textAlign = TextAlign.Center
            )
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(if (canIncrement) SurfaceCard else SurfaceSoft.copy(alpha = 0.3f))
                    .clickable(enabled = canIncrement) { onIncrement() }
                    .padding(0.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "+",
                    style = MaterialTheme.typography.titleMedium,
                    color = if (canIncrement) Ink else MutedSoft.copy(alpha = 0.3f)
                )
            }
        }
    }
}

@Composable
private fun SettingsToggleItem(
    label: String,
    description: String,
    checked: Boolean,
    onToggle: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.titleMedium,
                color = Ink
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = { onToggle() },
            colors = SwitchDefaults.colors(
                checkedThumbColor = OnPrimary,
                checkedTrackColor = Primary,
                uncheckedThumbColor = Ink,
                uncheckedTrackColor = SurfaceSoft
            )
        )
    }
}

private fun levelLabel(level: String): String = when (level) {
    "LOW" -> "初级"
    "MEDIUM" -> "中级"
    "HIGH" -> "高级"
    else -> level
}

private fun levelDescription(level: String): String = when (level) {
    "LOW" -> "初级 · LOW"
    "MEDIUM" -> "中级 · MEDIUM"
    "HIGH" -> "高级 · HIGH"
    else -> level
}

private fun translationModeLabel(mode: String): String = when (mode) {
    "FULL" -> "完全显示"
    "DIM" -> "淡化"
    "BLURRED" -> "模糊"
    "HIDDEN" -> "隐藏"
    else -> mode
}

// ── Info tip button (ℹ️) ──

@Composable
private fun InfoTipButton(onClick: () -> Unit) {
    Text(
        text = "ℹ",
        style = MaterialTheme.typography.titleSmall,
        color = MutedSoft,
        modifier = Modifier
            .clickable { onClick() }
            .padding(8.dp)
    )
}

// ── Info dialog (ℹ️ clicked) ──

@Composable
private fun SettingsInfoDialog(
    title: String,
    message: String,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onConfirm,
        title = {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
        },
        text = {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = Ink
            )
        },
        confirmButton = {
            Text(
                text = "知道了",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = Primary,
                modifier = Modifier
                    .clickable { onConfirm() }
                    .padding(horizontal = 16.dp, vertical = 10.dp)
            )
        },
        containerColor = SurfaceCard,
        titleContentColor = Ink
    )
}

// ── Confirm dialog (setting change confirmation) ──

@Composable
private fun SettingsConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
        },
        text = {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = Ink
            )
        },
        confirmButton = {
            Text(
                text = confirmLabel,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = Primary,
                modifier = Modifier
                    .clickable { onConfirm() }
                    .padding(horizontal = 16.dp, vertical = 10.dp)
            )
        },
        dismissButton = {
            Text(
                text = "取消",
                style = MaterialTheme.typography.labelLarge,
                color = Muted,
                modifier = Modifier
                    .clickable { onDismiss() }
                    .padding(horizontal = 16.dp, vertical = 10.dp)
            )
        },
        containerColor = SurfaceCard,
        titleContentColor = Ink
    )
}
