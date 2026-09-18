import 'package:contexta/pad/pad_login_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 平板登录入口测试。
///
/// 守的是一条**功能可达性**：平板上这是唯一能登录的地方，丢了它平板就永远
/// 停在本地模式（同步不跑、首页只有安装时那批文章）。
void main() {
  testWidgets('显示未登录状态与登录按钮，点击回调', (tester) async {
    var logins = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: PadLoginBanner(onLogin: () => logins++)),
        ),
      ),
    );

    expect(find.text('登录'), findsOneWidget);
    expect(find.textContaining('未登录'), findsOneWidget);

    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(logins, 1);
  });

  testWidgets('登录按钮触摸目标不小于 44dp（平板手指点击）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: PadLoginBanner(onLogin: () {}))),
      ),
    );

    final size = tester.getSize(find.widgetWithText(TextButton, '登录'));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
