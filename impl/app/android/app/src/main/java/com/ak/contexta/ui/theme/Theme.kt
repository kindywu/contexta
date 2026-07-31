package com.ak.contexta.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val ContextaLightColorScheme = lightColorScheme(
    primary = Primary,
    onPrimary = OnPrimary,
    primaryContainer = SurfaceStrong,
    onPrimaryContainer = Ink,
    secondary = BodyText,
    onSecondary = OnPrimary,
    secondaryContainer = SurfaceSoft,
    onSecondaryContainer = Ink,
    tertiary = MutedSoft,
    onTertiary = OnPrimary,
    background = Background,
    onBackground = Ink,
    surface = SurfaceCard,
    onSurface = Ink,
    surfaceVariant = SurfaceSoft,
    onSurfaceVariant = BodyText,
    outline = Hairline,
    outlineVariant = HairlineSoft,
    error = Error,
    onError = OnPrimary
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
