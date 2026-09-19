import 'package:contexta/core/theme/app_colors.dart';
import 'package:contexta/core/theme/app_dimens.dart';
import 'package:contexta/core/theme/app_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阅读页样式是「分页测量 = 渲染」的唯一真源：数值变了必须显式改这里，
/// 否则 ArticlePaginator 会算出与实际渲染不符的页高。
void main() {
  test('readingBody 为 22sp / 34sp 行高 / ink', () {
    expect(AppType.readingBody.fontSize, 22);
    expect(AppType.readingBody.height, closeTo(34 / 22, 1e-9));
    expect(AppType.readingBody.color, AppColors.ink);
  });

  test('readingTranslation 为 17sp / 25sp 行高 / muted', () {
    expect(AppType.readingTranslation.fontSize, 17);
    expect(AppType.readingTranslation.height, closeTo(25 / 17, 1e-9));
    expect(AppType.readingTranslation.color, AppColors.muted);
  });

  test('readingTitle 为 displayMedium 28sp 且染 ink', () {
    expect(AppType.readingTitle.fontSize, 28);
    expect(AppType.readingTitle.fontFamily, 'serif');
    expect(AppType.readingTitle.color, AppColors.ink);
  });

  test('阅读间距 token：段内 16 / 段间 28', () {
    expect(AppReading.enToTranslationGap, 16);
    expect(AppReading.paragraphGap, 28);
  });
}
