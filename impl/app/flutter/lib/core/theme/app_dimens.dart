/// Contexta 设计系统尺寸 token（对照 Kotlin ui/theme/Dimens.kt）。
///
/// Spacing 为 4dp 基数；Radius 被组件实际引用；Page 为页面级布局常量。
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadius {
  static const double sm = 8; // 按钮、输入框、例句块、字母/音标网格格
  static const double md = 12; // 卡片、复习单词卡
  static const double lg = 16; // Modal 面板、Stepper 圆形按钮、Onboarding 选项卡
  static const double pill = 999; // 徽章、胶囊
}

abstract final class AppPage {
  static const double horizontalPadding = 20;
  static const double bottomPadding = 96;
  static const double minTouchTarget = 44;
}

/// 阅读页正文排版间距（手机 / 平板共用）。
///
/// 手机上由 `_ReadingParagraph` / `ReadingParagraph` 渲染，平板上还要被
/// `ArticlePaginator` 离线测高——**测量与渲染必须引用同一份常量**，各写一份
/// 字面量会漂移成「测量页高 ≠ 实际渲染高」，表现为溢出页底。
abstract final class AppReading {
  /// 英文正文 → 中文译文
  static const double enToTranslationGap = 16;

  /// 段落之间（译文底 → 下一段英文顶）。段间距算在前一段的块高里，块间无额外
  /// 间距——否则分页测量需要知道「本段是否落在页首」才能减掉，复杂且易错。
  static const double paragraphGap = 28;
}

/// 动效时长（对照 Kotlin ui/theme/Motion.kt；原型 150/200/300ms）。
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
}
