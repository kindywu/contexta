import 'package:contexta/core/theme/app_type.dart';
import 'package:contexta/pad/reading/article_paginator.dart';
import 'package:contexta/pad/reading/reading_block.dart';
import 'package:contexta/ui/reading/translation_visibility.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ArticlePaginator buildPaginator() => ArticlePaginator(
  bodyStyle: AppType.readingBody,
  translationStyle: AppType.readingTranslation,
  titleStyle: AppType.readingTitle,
  buttonLabelStyle: AppType.textTheme.titleSmall!,
);

PaginatedArticle paginate(
  List<ReadingBlock> blocks, {
  double pageWidth = 530,
  double pageHeight = 600,
  TranslationMode mode = TranslationMode.full,
  TextScaler bodyTextScaler = TextScaler.noScaling,
  TextScaler labelTextScaler = TextScaler.noScaling,
}) => buildPaginator().paginate(
  blocks: blocks,
  pageWidth: pageWidth,
  pageHeight: pageHeight,
  bodyTextScaler: bodyTextScaler,
  labelTextScaler: labelTextScaler,
  translationMode: mode,
);

const shortA = ParagraphBlock(index: 0, englishText: 'It is a sunny day.', chineseTranslation: '这是晴天。');
const shortB = ParagraphBlock(index: 1, englishText: 'The sky is blue.', chineseTranslation: '天空是蓝的。');
const shortC = ParagraphBlock(index: 2, englishText: 'Birds are singing.', chineseTranslation: '鸟儿在唱歌。');

void main() {
  test('页高足够时全部块落在一页', () {
    final result = paginate([shortA, shortB, shortC], pageHeight: 2000);
    expect(result.pages.length, 1);
    expect(result.pages.single.blocks.length, 3);
    expect(result.pages.single.overflows, isFalse);
  });

  test('页高不足时按块边界换页', () {
    final result = paginate([shortA, shortB, shortC], pageHeight: 60);
    expect(result.pages.length, 3);
    for (final page in result.pages) {
      expect(page.blocks.length, 1);
    }
  });

  test('段落 → 页映射正确', () {
    final result = paginate([shortA, shortB, shortC], pageHeight: 60);
    expect(result.pageOf(0), 0);
    expect(result.pageOf(1), 1);
    expect(result.pageOf(2), 2);
    expect(result.pageOf(99), isNull);
  });

  test('空块列表产出 1 个空页（不返回 0 页）', () {
    final result = paginate(const []);
    expect(result.pages.length, 1);
    expect(result.pages.single.blocks, isEmpty);
  });

  test('单块超过整页高时独占一页并标记 overflows', () {
    final huge = ParagraphBlock(
      index: 0,
      englishText: List.filled(60, 'Extraordinarily long sentence here.').join(' '),
      chineseTranslation: '很长的段落。',
    );
    // 后面这块用 shortB（index: 1）：shortA 也是 index: 0，与 huge 重复，
    // 会让 pageOfParagraph 的段落下标互相覆盖。
    final result = paginate([huge, shortB], pageHeight: 120);
    expect(result.pages.first.overflows, isTrue);
    expect(result.pages.first.blocks.length, 1);
    expect(result.pageOf(0), 0);
    expect(result.pageOf(1), 1);
  });

  test('译文隐藏时段落更矮（同页能装下更多）', () {
    final full = paginate([shortA, shortB, shortC], pageHeight: 200);
    final hidden = paginate([shortA, shortB, shortC], pageHeight: 200, mode: TranslationMode.hidden);
    expect(hidden.pages.length, lessThanOrEqualTo(full.pages.length));
    expect(hidden.pages.first.usedHeight, lessThan(full.pages.first.usedHeight));
  });

  test('spreadCount 按两页一跨页向上取整', () {
    expect(paginate([shortA, shortB, shortC], pageHeight: 60).spreadCount, 2);
    expect(paginate([shortA], pageHeight: 2000).spreadCount, 1);
  });

  test('标题块高度含分隔线与上下间距', () {
    final withTitle = paginate([const TitleBlock('A Title'), shortA], pageHeight: 2000);
    final withoutTitle = paginate([shortA], pageHeight: 2000);
    expect(
      withTitle.pages.single.usedHeight - withoutTitle.pages.single.usedHeight,
      greaterThan(40), // 16 + 1 + 24 = 41 再加标题文字高度
    );
  });

  test('超大页宽下文本占用行数减少（测量确实受宽度影响）', () {
    final narrow = paginate([shortA], pageWidth: 100, pageHeight: 2000);
    final wide = paginate([shortA], pageWidth: 1000, pageHeight: 2000);
    expect(narrow.pages.single.usedHeight, greaterThan(wide.pages.single.usedHeight));
  });

  test('正文/标题与译文/按钮各用各的 textScaler', () {
    // 正文与标题是 RichText（不吃系统字体缩放），译文与按钮是 Text（吃）；
    // 拆成两个 scaler 就是为了让测量与各自渲染器一致。
    final base = paginate([shortA], pageHeight: 2000);
    final scaledLabel = paginate(
      [shortA],
      pageHeight: 2000,
      labelTextScaler: TextScaler.linear(2),
    );
    final scaledBody = paginate(
      [shortA],
      pageHeight: 2000,
      bodyTextScaler: TextScaler.linear(2),
    );

    // 放大 label scaler 只影响译文 → 整段更高（证明它确实传到了译文测量）
    expect(
      scaledLabel.pages.single.usedHeight - base.pages.single.usedHeight,
      greaterThan(0),
    );
    // 放大 body scaler 影响的是英文正文 → 同样变高（证明它传到了正文测量）
    expect(
      scaledBody.pages.single.usedHeight - base.pages.single.usedHeight,
      greaterThan(0),
    );
    // 两个 scaler 命中的是不同文本 → 两种放大的结果不相等
    expect(
      scaledBody.pages.single.usedHeight,
      isNot(scaledLabel.pages.single.usedHeight),
    );
  });
}
