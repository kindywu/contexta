import 'package:flutter/widgets.dart';

import '../../core/theme/app_type.dart';
import 'article_paginator.dart';

/// 构造平板分页器——**测量样式与渲染样式逐字段对齐**。
///
/// `ArticlePaginator` 是离线的（纯 `TextPainter`，没有 BuildContext），但书页
/// 里同一段文字的渲染走两条不同路径，二者对 ambient 样式的处理**不一样**：
///
/// | 内容 | 渲染器 | 是否并 ambient `DefaultTextStyle` |
/// |------|--------|----------------------------------|
/// | 英文正文、文章标题 | 裸 `RichText` | **否** |
/// | 中文译文、按钮文字 | `Text` | **是**（`inherit: true` 时） |
///
/// 并进来的字段会改变文字度量：M3 主题给 `bodyMedium` 带了
/// `letterSpacing: 0.25`，`Text` 把它混进译文样式，而裸 `TextPainter` 看不到。
/// 于是**测量行宽偏窄**，恰好在换行边界的段落会被判成"放得下"，实际渲染多出
/// 一行，页底溢出。
///
/// 2026-09-18 实测：40 字中文译文在 562dp 页宽下，裸测量 1 行（22dp）、
/// 渲染 2 行（44dp）——整页溢出 11px。本函数就是那次修复的产物。
///
/// 因此：**走 `Text` 的样式先并 [ambientTextStyle]，走 `RichText` 的保持原样。**
/// 调用方传 `DefaultTextStyle.of(context).style`（书页外层就是渲染现场，
/// 中间没有别的 `DefaultTextStyle` 介入，两者必然一致）。
ArticlePaginator buildPadPaginator(TextStyle ambientTextStyle) {
  return ArticlePaginator(
    // RichText：不吃 DefaultTextStyle，原样测量
    bodyStyle: AppType.readingBody,
    titleStyle: AppType.readingTitle,
    // Text：渲染时会并 ambient，测量必须同样并上
    translationStyle: ambientTextStyle.merge(AppType.readingTranslation),
    buttonLabelStyle: ambientTextStyle.merge(AppType.textTheme.titleSmall!),
  );
}
