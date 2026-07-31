package com.ak.contexta.ui.theme

import androidx.compose.ui.graphics.Color

// ─── Contexta Design System (warm-canvas editorial, per lingua prototype) ───

// Brand
val Primary = Color(0xFFCC785C)          // coral — buttons, links, accents
val PrimaryPressed = Color(0xFFA9583E)   // pressed state
val PrimaryDisabled = Color(0xFFE6DFD8)  // disabled — same as Hairline

// Canvas & surfaces (light only)
val Background = Color(0xFFFAF9F5)       // page canvas (warm cream)
val SurfaceSoft = Color(0xFFF5F0E8)      // hints, example blocks, dividers
val SurfaceCard = Color(0xFFEFE9DE)      // cards (one step deeper than canvas)
val SurfaceStrong = Color(0xFFE8E0D2)    // selected states, radio-card selected
val Hairline = Color(0xFFE6DFD8)         // 1px borders, separators
val HairlineSoft = Color(0xFFEBE6DF)     // faint separators

// Text
val Ink = Color(0xFF141413)              // titles + primary text (warm near-black)
val BodyStrong = Color(0xFF252523)
val BodyText = Color(0xFF3D3D3A)
val Muted = Color(0xFF6C6A64)
val MutedSoft = Color(0xFF8E8B82)
val OnPrimary = Color(0xFFFFFFFF)

// Semantic
val Amber = Color(0xFFE8A55A)            // bookmark states only
val Teal = Color(0xFF5DB8A6)             // secondary emphasis
val Success = Color(0xFF5DB872)
val Warning = Color(0xFFD4A017)
val Error = Color(0xFFC64545)

// Dark surfaces & scrim
val ToastDark = Color(0xFF181715)        // toast background
val Scrim = Color(0x59231815)            // rgba(24,23,21,0.35) — modal/sheet scrim

// ─── Deprecated aliases (old names → new values; delete in final L3 task) ───
@Deprecated("Use Primary") val Accent = Primary
@Deprecated("Use OnPrimary") val AccentOn = OnPrimary
@Deprecated("Use PrimaryPressed") val AccentHover = PrimaryPressed
@Deprecated("Use PrimaryPressed") val AccentActive = PrimaryPressed
@Deprecated("Use SurfaceCard") val Surface = SurfaceCard
@Deprecated("Use SurfaceSoft") val SurfaceWarm = SurfaceSoft
@Deprecated("Use Ink") val Foreground = Ink
@Deprecated("Use BodyText") val ForegroundSecondary = BodyText
@Deprecated("Use MutedSoft") val Meta = MutedSoft
@Deprecated("Use Hairline") val Border = Hairline
@Deprecated("Use HairlineSoft") val BorderSoft = HairlineSoft
@Deprecated("Use Warning") val Warn = Warning
@Deprecated("Use Error") val Danger = Error
