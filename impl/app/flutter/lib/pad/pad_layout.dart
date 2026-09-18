import 'package:flutter/widgets.dart';

import '../core/theme/app_dimens.dart';

/// 平板界面的布局常量——**只被 `lib/pad/` 消费**。
///
/// 平板是横屏定宽形态（本机 1280×800dp），但常量仍按"内容宽度"而非"设备
/// 坐标"表达：分屏、折叠屏展开、外接显示器下同一套规则照样成立。
///
/// 放在单独文件而不是塞进各页面：首页的两栏 + 网格、阅读页的书页 + 边距
/// 都引用同一批数字，散落各处必然漂移。
abstract final class PadLayout {
  /// 左侧常驻侧边栏宽度（图标 + 文字横排，见 `pad_shell.dart`）。
  ///
  /// 80dp 的窄 rail 是"手机底栏竖过来"的观感；加宽到 208dp 才像侧边栏，
  /// 也容得下「Contexta」字标与分组标题。
  static const double sidebarWidth = 208;

  /// 内容区左右留白。
  ///
  /// 32dp（而非手机常用的 20dp）：平板视野宽，留白太窄会让内容贴边；
  /// 但也不能像浏览器那样给到 48dp+，否则 3 列网格会掉成 2 列。
  static const double pagePadding = 32;

  /// 内容区最大宽度（超宽屏居中，避免正文行长失控）。
  static const double maxContentWidth = 1440;

  /// 通用栏间距。
  static const double gap = AppSpacing.lg;

  // ── 首页 ──

  /// 日期索引列宽度（首页左栏目录）。
  ///
  /// 180dp 是"容得下 `2026年8月11日` + `3/5` 且不挤掉第 3 列卡片"的宽度：
  /// 再宽一格，右侧网格就从 3 列掉到 2 列。
  static const double dateIndexWidth = 180;

  /// 日期索引与文章网格之间的间距。
  static const double dateIndexGap = AppSpacing.xl;

  /// Hero 卡（继续阅读）内边距。
  static const EdgeInsets heroPadding = EdgeInsets.all(AppSpacing.xl);

  /// Hero 卡圆角。
  static const double heroRadius = AppRadius.lg;

  // ── 文章网格 ──

  /// 卡片最小可用宽度。再窄标题换行会碎，退化回手机观感。
  static const double cardMinWidth = 240;

  /// 封面块高度（卡片上半的"书封"）。
  static const double cardCoverHeight = 110;

  /// 网格列数上限（超宽屏下不无限铺开）。
  static const int gridMaxColumns = 4;

  // ── 阅读页 ──

  /// 书页内容区最大宽度（单页正文不超过可读行宽）。
  static const double spreadMaxWidth = 1180;

  /// 中缝宽度（含中心 1px 竖线）。
  static const double spreadGutter = 56;

  /// 页边翻页热区最小宽度。窄于此不启用（退化为仅横滑翻页），避免误触。
  static const double edgeTapMinWidth = 44;

  /// 书页底部让出的那条带：收起态放页码胶囊，唤出态被底栏**正好铺满**。
  ///
  /// 与 [chromeBottomBarHeight] 取同一个值是有意的：底栏是覆盖层，如果它比
  /// 让出的带更高，唤出时就会压住页面最后一行——而最后一行正是读者眼睛所在
  /// 的位置。取齐之后，唤出工具栏永远不会遮住任何正文。
  static const double pagePillRowHeight = 56;

  /// 上下滑入栏的高度。
  ///
  /// 顶栏比底栏"薄"一层：它是纯覆盖层（书页不为它让位），压住的是第一页
  /// 的标题行——而顶栏本身就在显示同一个标题，读者不会因此丢失信息。
  /// 底栏则必须与 [pagePillRowHeight] 取齐（理由见上）。
  static const double chromeTopBarHeight = 56;
  static const double chromeBottomBarHeight = 56;

  /// 页内上下留白。
  static const double pageTopPadding = 16;
  static const double pageBottomPadding = 8;
}
