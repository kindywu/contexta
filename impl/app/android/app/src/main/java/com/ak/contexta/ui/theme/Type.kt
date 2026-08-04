package com.ak.contexta.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// ─── Contexta Typography — lingua prototype type scale (px→sp) ───
// Display serif: weight 400, NEVER bold (prototype rule). Body: Inter-like sans.

private val DisplayFontFamily = FontFamily.Serif
private val BodyFontFamily = FontFamily.SansSerif

val ContextaTypography = Typography(
    // display-md 36px serif 400 — hero titles
    displayLarge = TextStyle(
        fontFamily = DisplayFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 36.sp,
        lineHeight = 41.sp,
        letterSpacing = (-0.5).sp
    ),
    // display-sm 28px serif 400 — page titles
    displayMedium = TextStyle(
        fontFamily = DisplayFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 28.sp,
        lineHeight = 34.sp,
        letterSpacing = (-0.3).sp
    ),
    // title-lg 22px serif 500 — card hero titles
    headlineLarge = TextStyle(
        fontFamily = DisplayFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 22.sp,
        lineHeight = 29.sp
    ),
    // title-md 18px serif 500 — card titles
    headlineMedium = TextStyle(
        fontFamily = DisplayFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 18.sp,
        lineHeight = 25.sp
    ),
    // title-sm 16px sans 500 — list labels
    headlineSmall = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 16.sp,
        lineHeight = 22.sp
    ),
    // app bar / screen header titles
    titleLarge = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 18.sp,
        lineHeight = 25.sp
    ),
    // card titles / list items
    titleMedium = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 16.sp,
        lineHeight = 22.sp
    ),
    // buttons, small labels
    titleSmall = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp
    ),
    // body-md 16px — body text（阅读页正文局部覆盖为 18sp / 30sp，见 ReadingScreen）
    bodyLarge = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 25.sp
    ),
    // body-sm 14px — secondary text
    bodyMedium = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 22.sp
    ),
    // caption 13px — hints
    bodySmall = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 18.sp
    ),
    // button label 14px / 500
    labelLarge = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp
    ),
    // caption 13px / 500 — badges
    labelMedium = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 13.sp,
        lineHeight = 18.sp
    ),
    // caption-upper 12px / 500 / +1.5sp — uppercase section labels
    labelSmall = TextStyle(
        fontFamily = BodyFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 17.sp,
        letterSpacing = 1.5.sp
    )
)

/**
 * Phonetic (IPA) style: default sans-serif + coral.
 * NOTE: 早期用 Monospace（原型风格），但部分厂商 ROM（如 HyperOS）等宽字体链缺少 IPA 字形块，
 * 导致音标乱码；改用系统默认无衬线字体，依赖系统 fallback 链补齐 IPA 字形（与重构前行为一致）。
 */
val PhoneticStyle = TextStyle(
    fontWeight = FontWeight.Normal,
    fontSize = 14.sp,
    lineHeight = 22.sp,
    color = Primary
)
