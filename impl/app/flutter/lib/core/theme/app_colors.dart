import 'package:flutter/material.dart';

/// Contexta 设计系统颜色 token（对照 Kotlin ui/theme/Color.kt，warm-canvas
/// editorial 风格；light only，无深色模式）。
///
/// 页面与组件只消费这里的命名色，不写死色值。
abstract final class AppColors {
  // ─── Brand ───
  /// 珊瑚强调：主按钮、链接、进度条、选中态、音标
  static const Color primary = Color(0xFFCC785C);
  static const Color primaryPressed = Color(0xFFA9583E);
  static const Color primaryDisabled = Color(0xFFE6DFD8);

  // ─── Canvas & surfaces ───
  static const Color background = Color(0xFFFAF9F5);
  static const Color surfaceSoft = Color(0xFFF5F0E8);
  static const Color surfaceCard = Color(0xFFEFE9DE);
  static const Color surfaceStrong = Color(0xFFE8E0D2);
  static const Color hairline = Color(0xFFE6DFD8);
  static const Color hairlineSoft = Color(0xFFEBE6DF);

  // ─── Text ───
  static const Color ink = Color(0xFF141413);
  static const Color bodyStrong = Color(0xFF252523);
  static const Color bodyText = Color(0xFF3D3D3A);
  static const Color muted = Color(0xFF6C6A64);
  static const Color mutedSoft = Color(0xFF8E8B82);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // ─── Semantic ───
  static const Color amber = Color(0xFFE8A55A);
  static const Color teal = Color(0xFF5DB8A6);
  static const Color success = Color(0xFF5DB872);
  static const Color warning = Color(0xFFD4A017);
  static const Color error = Color(0xFFC64545);

  // ─── Dark surfaces & scrim ───
  static const Color toastDark = Color(0xFF181715);
  static const Color scrim = Color(0x59231815);
}
