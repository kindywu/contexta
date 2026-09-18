import 'package:flutter/material.dart';

import '../core/theme/app_dimens.dart';
import '../ui/home/home_controller.dart';
import 'pad_article_card.dart';
import 'pad_layout.dart';

/// 由可用宽度推导网格列数——**不写死设备尺寸**，任意内容宽度都能得到不
/// 溢出的列数：1 列（< 2×最小卡宽）… 最多 [PadLayout.gridMaxColumns] 列。
///
/// 本机 1280dp 横屏代入：内容区 1072 − 左右留白 64 − 日期索引 180 − 间距 32
/// = 796dp → **3 列**，每列 249dp。
int padGridColumns(double maxWidth, {double gap = AppSpacing.lg}) {
  // n 列时可用宽 = n×card + (n-1)×gap ≥ n×min + (n-1)×gap
  final columns = ((maxWidth + gap) / (PadLayout.cardMinWidth + gap)).floor();
  return columns.clamp(1, PadLayout.gridMaxColumns);
}

/// Pad 文章网格：封面式卡片，按 [padGridColumns] 分行，**每行等高**。
///
/// 为什么不用 `Wrap`：`Wrap` 的子项各按自身内容取高，同一行里标题两行的
/// 卡片会比标题一行的卡片高出一截，封面色块的高度参差不齐——而封面块正是
/// 这个网格的扫视锚点，错位会毁掉"按色块快速定位"的效果。这里显式分行 +
/// `IntrinsicHeight` 把整行拉到该行最高卡片的高度。
class PadArticleGrid extends StatelessWidget {
  const PadArticleGrid({
    super.key,
    required this.articles,
    required this.onArticleClick,
  });

  final List<ArticleItemUi> articles;
  final ValueChanged<int> onArticleClick;

  static const double _gap = AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = padGridColumns(constraints.maxWidth, gap: _gap);
        final rows = <Widget>[];
        for (var start = 0; start < articles.length; start += columns) {
          final end = (start + columns).clamp(0, articles.length);
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: start == 0 ? 0 : _gap),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = start; i < end; i++) ...[
                      if (i > start) const SizedBox(width: _gap),
                      Expanded(
                        child: PadArticleCard(
                          article: _toCardData(articles[i]),
                          onClick: () => onArticleClick(articles[i].id),
                        ),
                      ),
                    ],
                    // 末行不足列数：右侧补占位，卡片宽度与其它行保持一致
                    for (var i = end; i < start + columns; i++) ...[
                      if (i > start) const SizedBox(width: _gap),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }

  PadArticleCardData _toCardData(ArticleItemUi article) => PadArticleCardData(
    id: article.id,
    title: article.title,
    difficultyLabel: article.difficultyLabel,
    categoryLabel: article.categoryLabel,
    isReadCompleted: article.isReadCompleted,
  );
}
