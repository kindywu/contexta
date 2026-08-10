import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Contexta 设计系统文字阶梯（对照 Kotlin ui/theme/Type.kt）。
///
/// - display 级 serif 恒为 400 绝不加粗（原型铁律），负字距
/// - headline 级 serif 500；正文/标签 sans 400/500
/// - 不打包字体文件：用系统字体族，依赖系统 fallback 链渲染 IPA 音标
abstract final class AppType {
  static const TextTheme textTheme = TextTheme(
    // display-md 36px serif 400 — hero 标题（Onboarding logo）
    displayLarge: TextStyle(
      fontFamily: 'serif',
      fontWeight: FontWeight.w400,
      fontSize: 36,
      height: 41 / 36,
      letterSpacing: -0.5,
    ),
    // display-sm 28px serif 400 — 页面标题（AppTopBar、Home 问候语、
    // Onboarding 步骤标题、Reading 正文顶部文章标题）
    displayMedium: TextStyle(
      fontFamily: 'serif',
      fontWeight: FontWeight.w400,
      fontSize: 28,
      height: 34 / 28,
      letterSpacing: -0.3,
    ),
    // title-lg 22px serif 500 — 卡片大标题（复习完成、AddWord 单词详情）
    headlineLarge: TextStyle(
      fontFamily: 'serif',
      fontWeight: FontWeight.w500,
      fontSize: 22,
      height: 29 / 22,
    ),
    // title-md 18px serif 500 — 卡片标题（ArticleCard、StatCard 数字）
    headlineMedium: TextStyle(
      fontFamily: 'serif',
      fontWeight: FontWeight.w500,
      fontSize: 18,
      height: 25 / 18,
    ),
    // title-sm 16px sans 500 — 列表标签（InlineTabs、radio-card）
    headlineSmall: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 16,
      height: 22 / 16,
    ),
    // 屏幕标题位（阶梯保留，当前页面未直接引用）
    titleLarge: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 18,
      height: 25 / 18,
    ),
    // 列表项/标签（设置行、DayGroup 日期行）
    titleMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 16,
      height: 22 / 16,
    ),
    // 按钮文字、BottomNav 标签、语法卡片标题
    titleSmall: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 14,
      height: 20 / 14,
    ),
    // body-md 16px 正文（阅读页正文局部覆盖为 18sp / 30sp 行高）
    bodyLarge: TextStyle(
      fontSize: 16,
      height: 25 / 16,
    ),
    // body-sm 14px 辅助正文（Toast、设置行描述、例句）
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 22 / 14,
    ),
    // caption 13px 说明、小字
    bodySmall: TextStyle(
      fontSize: 13,
      height: 18 / 13,
    ),
    // button label 14px/500（弹窗按钮、AddWord 词性标签）
    labelLarge: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 14,
      height: 20 / 14,
    ),
    // caption 13px/500 徽标、语速胶囊、进度计数
    labelMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 13,
      height: 18 / 13,
    ),
    // caption-upper 12px/500/+1.5sp 全大写分组标签、已读标记
    labelSmall: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 12,
      height: 17 / 12,
      letterSpacing: 1.5,
    ),
  );

  /// 音标（IPA）样式：默认无衬线 + 珊瑚色。
  ///
  /// ⚠️ 不用等宽字体：部分厂商 ROM（如小米 HyperOS）等宽字体链缺少 IPA
  /// 字形块导致音标乱码；依赖系统默认无衬线 fallback 链补齐 IPA 字形。
  static const TextStyle phonetic = TextStyle(
    fontSize: 14,
    height: 22 / 14,
    color: AppColors.primary,
  );
}
