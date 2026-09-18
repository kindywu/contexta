import 'package:contexta/core/layout/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('windowSizeFor 断点', () {
    test('窄屏为 compact', () {
      expect(windowSizeFor(360), WindowSize.compact);
      expect(windowSizeFor(599.9), WindowSize.compact);
    });

    test('600 起为 medium', () {
      expect(windowSizeFor(600), WindowSize.medium);
      expect(windowSizeFor(813), WindowSize.medium); // pad 竖屏
      expect(windowSizeFor(839.9), WindowSize.medium);
    });

    test('840 起为 expanded', () {
      expect(windowSizeFor(840), WindowSize.expanded);
      expect(windowSizeFor(1219), WindowSize.expanded); // pad 横屏
    });
  });

  testWidgets('扩展从 MediaQuery 读宽度', (tester) async {
    late WindowSize size;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1219, 813)),
        child: Builder(
          builder: (context) {
            size = context.windowSize;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(size, WindowSize.expanded);
  });

  testWidgets('isPadLayout 在 compact 为 false', (tester) async {
    late bool pad;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Builder(
          builder: (context) {
            pad = context.isPadLayout;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(pad, isFalse);
  });
}
