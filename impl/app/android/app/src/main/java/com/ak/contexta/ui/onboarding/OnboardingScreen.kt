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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.AutoStories
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.WorkspacePremium
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Hairline
import com.ak.contexta.ui.theme.Ink
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.MutedSoft
import com.ak.contexta.ui.theme.OnPrimary
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.PrimaryDisabled
import com.ak.contexta.ui.theme.SurfaceCard
import com.ak.contexta.ui.theme.SurfaceStrong

@Composable
fun OnboardingScreen(
    onComplete: () -> Unit,
    viewModel: OnboardingViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    // Auto-redirect to Home if user already completed onboarding
    LaunchedEffect(Unit) {
        if (viewModel.isAlreadyOnboarded()) {
            onComplete()
        }
    }

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
            style = MaterialTheme.typography.displayLarge
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "语境 · 沉浸式英语阅读",
            style = MaterialTheme.typography.bodyMedium,
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
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = Ink
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
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Primary,
                    contentColor = OnPrimary,
                    disabledContainerColor = PrimaryDisabled.copy(alpha = 0.5f),
                    disabledContentColor = MutedSoft
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
            style = MaterialTheme.typography.displayMedium
        )
        Spacer(modifier = Modifier.height(24.dp))

        LevelOption(
            value = "LOW",
            label = "初级 · LOW",
            desc = "小学、初中水平，从基础开始",
            isSelected = selectedLevel == "LOW",
            onClick = { onSelectLevel("LOW") },
            icon = Icons.Outlined.School
        )
        LevelOption(
            value = "MEDIUM",
            label = "中级 · MEDIUM",
            desc = "高中、大学四六级水平",
            isSelected = selectedLevel == "MEDIUM",
            onClick = { onSelectLevel("MEDIUM") },
            icon = Icons.Outlined.AutoStories
        )
        LevelOption(
            value = "HIGH",
            label = "高级 · HIGH",
            desc = "专八、托福、雅思水平",
            isSelected = selectedLevel == "HIGH",
            onClick = { onSelectLevel("HIGH") },
            icon = Icons.Outlined.WorkspacePremium
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
            style = MaterialTheme.typography.displayMedium
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
            style = MaterialTheme.typography.displayMedium
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
                .background(SurfaceCard)
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Outlined.MenuBook,
                contentDescription = null,
                tint = Primary,
                modifier = Modifier.size(40.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "你的专属阅读之旅即将开始",
                style = MaterialTheme.typography.titleMedium
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
                color = Primary,
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
    onClick: () -> Unit,
    icon: ImageVector
) {
    val borderColor = if (isSelected) Primary else Hairline
    val bgColor = if (isSelected) SurfaceStrong else SurfaceCard

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
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (isSelected) Primary else MutedSoft,
            modifier = Modifier.size(28.dp)
        )
        Spacer(modifier = Modifier.width(10.dp))
        Box(
            modifier = Modifier
                .size(22.dp)
                .clip(CircleShape)
                .border(2.dp, if (isSelected) Primary else Hairline, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .clip(CircleShape)
                        .background(Primary)
                )
            }
        }
        Spacer(modifier = Modifier.width(14.dp))
        Column {
            Text(text = label, style = MaterialTheme.typography.titleMedium)
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
    val borderColor = if (isSelected) Primary else Hairline
    val bgColor = if (isSelected) SurfaceStrong else SurfaceCard

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
                .border(2.dp, if (isSelected) Primary else Hairline, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .clip(CircleShape)
                        .background(Primary)
                )
            }
        }
        Spacer(modifier = Modifier.width(14.dp))
        Column {
            Text(text = label, style = MaterialTheme.typography.titleMedium)
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
                            isActive -> Primary
                            isDone -> Primary.copy(alpha = 0.4f)
                            else -> Hairline
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
