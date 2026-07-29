package com.ak.contexta.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val ContextaLightColorScheme = lightColorScheme(
    primary = Accent,
    onPrimary = AccentOn,
    primaryContainer = SurfaceWarm,
    onPrimaryContainer = Foreground,
    secondary = ForegroundSecondary,
    onSecondary = AccentOn,
    secondaryContainer = SurfaceWarm,
    onSecondaryContainer = Foreground,
    tertiary = Meta,
    onTertiary = AccentOn,
    background = Background,
    onBackground = Foreground,
    surface = Surface,
    onSurface = Foreground,
    surfaceVariant = SurfaceWarm,
    onSurfaceVariant = ForegroundSecondary,
    outline = Border,
    outlineVariant = BorderSoft,
    error = Danger,
    onError = AccentOn
)

@Composable
fun ContextaTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = ContextaLightColorScheme,
        typography = ContextaTypography,
        content = content
    )
}
