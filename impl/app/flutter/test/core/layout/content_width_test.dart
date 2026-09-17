import 'package:contexta/core/layout/content_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('窄屏下不改变布局（占满可用宽）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ContentWidth(child: Text('x', textDirection: TextDirection.ltr)),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ContentWidth)).width, 800);
  });

  testWidgets('宽屏下子内容被限宽居中', (tester) async {
    tester.view.physicalSize = const Size(2438, 1626);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ContentWidth(child: SizedBox.expand()))),
    );
    final width = tester.getSize(find.byType(SizedBox).last).width;
    expect(width, 640);
  });

  testWidgets('可自定义 maxWidth', (tester) async {
    tester.view.physicalSize = const Size(2438, 1626);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ContentWidth(maxWidth: 560, child: SizedBox.expand()),
        ),
      ),
    );
    expect(tester.getSize(find.byType(SizedBox).last).width, 560);
  });
}
