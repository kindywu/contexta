import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_type.dart';

/// Contexta 主题（对照 Kotlin ui/theme/Theme.kt 的 ContextaLightColorScheme）。
///
/// 仅 light，无深色模式（与原型一致）。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.surfaceStrong,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.bodyText,
    onSecondary: AppColors.onPrimary,
    secondaryContainer: AppColors.surfaceSoft,
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.mutedSoft,
    onTertiary: AppColors.onPrimary,
    // background/onBackground 已废弃：画布底色由 scaffoldBackgroundColor
    // 提供（M3 surface 直接用作卡片底）
    surface: AppColors.surfaceCard,
    onSurface: AppColors.ink,
    surfaceContainerHighest: AppColors.surfaceSoft,
    onSurfaceVariant: AppColors.bodyText,
    outline: AppColors.hairline,
    outlineVariant: AppColors.hairlineSoft,
    error: AppColors.error,
    onError: AppColors.onPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: AppType.textTheme,
    scaffoldBackgroundColor: AppColors.background,
  );
}
