package com.ak.contexta.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.theme.Accent
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Foreground
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.Surface

@Composable
fun OnboardingScreen(
    onComplete: () -> Unit,
    viewModel: OnboardingViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(40.dp))

        // Logo area
        Text(
            text = "Contexta",
            style = MaterialTheme.typography.headlineLarge,
            fontFamily = MaterialTheme.typography.headlineLarge.fontFamily,
            fontWeight = FontWeight.Medium
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "语境 · 沉浸式英语阅读",
            style = MaterialTheme.typography.bodyLarge,
            color = Muted
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Step content
        when (state.currentStep) {
            1 -> Step1Level(
                selectedLevel = state.selectedLevel,
                onSelectLevel = { viewModel.selectLevel(it) }
            )
            2 -> Step2DailyCount(
                selectedCount = state.selectedDailyCount,
                onSelectCount = { viewModel.selectDailyCount(it) }
            )
            3 -> Step3Confirmation(
                level = state.selectedLevel ?: "",
                dailyCount = state.selectedDailyCount ?: 0
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        // Progress dots
        ProgressDots(currentStep = state.currentStep)

        Spacer(modifier = Modifier.height(16.dp))

        // Navigation buttons
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (state.currentStep > 1) {
                OutlinedButton(
                    onClick = { viewModel.previousStep() },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = Foreground
                    )
                ) {
                    Text("上一步")
                }
            }

            val canProceed = when (state.currentStep) {
                1 -> state.selectedLevel != null
                2 -> state.selectedDailyCount != null
                3 -> true
                else -> false
            }

            Button(
                onClick = {
                    if (state.currentStep < 3) {
                        viewModel.nextStep()
                    } else {
                        viewModel.completeOnboarding(onComplete)
                    }
                },
                enabled = canProceed,
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Accent,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                    disabledContainerColor = MaterialTheme.colorScheme.outline,
                    disabledContentColor = Muted
                )
            ) {
                Text(if (state.currentStep < 3) "下一步" else "开始学习")
            }
        }

        Spacer(modifier = Modifier.height(32.dp))
    }
}

@Composable
private fun Step1Level(
    selectedLevel: String?,
    onSelectLevel: (String) -> Unit
) {
    Column {
        Text(
            text = "选择你的英文水平",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(24.dp))

        LevelOption(
            value = "LOW",
            label = "初级 · LOW",
            desc = "小学、初中水平，从基础开始",
            isSelected = selectedLevel == "LOW",
            onClick = { onSelectLevel("LOW") }
        )
        LevelOption(
            value = "MEDIUM",
            label = "中级 · MEDIUM",
            desc = "高中、大学四六级水平",
            isSelected = selectedLevel == "MEDIUM",
            onClick = { onSelectLevel("MEDIUM") }
        )
        LevelOption(
            value = "HIGH",
            label = "高级 · HIGH",
            desc = "专八、托福、雅思水平",
            isSelected = selectedLevel == "HIGH",
            onClick = { onSelectLevel("HIGH") }
        )
    }
}

@Composable
private fun Step2DailyCount(
    selectedCount: Int?,
    onSelectCount: (Int) -> Unit
) {
    Column {
        Text(
            text = "每日文章数量",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "每天为你生成几篇文章？",
            style = MaterialTheme.typography.bodyMedium,
            color = Muted
        )
        Spacer(modifier = Modifier.height(20.dp))

        CountOption(
            count = 1,
            label = "1 篇",
            desc = "轻松起步",
            isSelected = selectedCount == 1,
            onClick = { onSelectCount(1) }
        )
        CountOption(
            count = 3,
            label = "3 篇",
            desc = "适中节奏",
            isSelected = selectedCount == 3,
            onClick = { onSelectCount(3) }
        )
        CountOption(
            count = 5,
            label = "5 篇",
            desc = "充分练习",
            isSelected = selectedCount == 5,
            onClick = { onSelectCount(5) }
        )
    }
}

@Composable
private fun Step3Confirmation(
    level: String,
    dailyCount: Int
) {
    Column {
        Text(
            text = "准备好了！",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "系统将根据你的设置，每天推送匹配水平的英文文章。首次生成需要一些时间，请稍候。",
            style = MaterialTheme.typography.bodyMedium,
            color = Muted
        )
        Spacer(modifier = Modifier.height(24.dp))

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(Surface)
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(text = "📖", style = MaterialTheme.typography.headlineLarge)
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "你的专属阅读之旅即将开始",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "每天坚持阅读，不知不觉提升英语",
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "水平：${levelLabel(level)}   |   每日 ${dailyCount} 篇",
                style = MaterialTheme.typography.bodyMedium,
                color = Accent,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun LevelOption(
    value: String,
    label: String,
    desc: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val borderColor = if (isSelected) Accent else MaterialTheme.colorScheme.outline
    val bgColor = if (isSelected) Accent.copy(alpha = 0.05f) else Surface

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(bgColor)
            .border(2.dp, borderColor, RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(22.dp)
                .clip(CircleShape)
                .border(2.dp, if (isSelected) Accent else MaterialTheme.colorScheme.outline, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .clip(CircleShape)
                        .background(Accent)
                )
            }
        }
        Spacer(modifier = Modifier.width(14.dp))
        Column {
            Text(text = label, fontWeight = FontWeight.Medium)
            Text(
                text = desc,
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        }
    }
}

@Composable
private fun CountOption(
    count: Int,
    label: String,
    desc: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val borderColor = if (isSelected) Accent else MaterialTheme.colorScheme.outline
    val bgColor = if (isSelected) Accent.copy(alpha = 0.05f) else Surface

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(bgColor)
            .border(2.dp, borderColor, RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(22.dp)
                .clip(CircleShape)
                .border(2.dp, if (isSelected) Accent else MaterialTheme.colorScheme.outline, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .clip(CircleShape)
                        .background(Accent)
                )
            }
        }
        Spacer(modifier = Modifier.width(14.dp))
        Column {
            Text(text = label, fontWeight = FontWeight.Medium)
            Text(
                text = desc,
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        }
    }
}

@Composable
private fun ProgressDots(currentStep: Int) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        repeat(3) { index ->
            val step = index + 1
            val isActive = step == currentStep
            val isDone = step < currentStep

            Box(
                modifier = Modifier
                    .height(8.dp)
                    .then(
                        if (isActive) Modifier.width(24.dp)
                        else Modifier.size(8.dp)
                    )
                    .clip(if (isActive) RoundedCornerShape(4.dp) else CircleShape)
                    .background(
                        when {
                            isActive -> Accent
                            isDone -> Accent.copy(alpha = 0.4f)
                            else -> MaterialTheme.colorScheme.outline
                        }
                    )
            )
        }
    }
}

private fun levelLabel(level: String): String = when (level) {
    "LOW" -> "初级"
    "MEDIUM" -> "中级"
    "HIGH" -> "高级"
    else -> level
}
