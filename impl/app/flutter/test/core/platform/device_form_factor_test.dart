import 'package:contexta/core/platform/device_form_factor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设备形态判定测试：**按显示屏尺寸**（不是窗口尺寸）分手机 / 平板。
///
/// 这层判定决定整棵界面树走哪一支，且必须在 `runApp` 之前出结果——判错等于
/// 整机跑错界面。守的重点因此是：断点边界、以及"拿不到显示屏尺寸"时的兜底。
void main() {
  group('formFactorForDisplay：物理尺寸 + 像素比 → 形态', () {
    test('手机（1080×2340 @3x = 360×780dp）→ phone', () {
      expect(
        formFactorForDisplay(
          physicalSize: const Size(1080, 2340),
          devicePixelRatio: 3.0,
        ),
        DeviceFormFactor.phone,
      );
    });

    test('平板横屏（2560×1600 @2x = 1280×800dp）→ pad', () {
      expect(
        formFactorForDisplay(
          physicalSize: const Size(2560, 1600),
          devicePixelRatio: 2.0,
        ),
        DeviceFormFactor.pad,
      );
    });

    test('平板竖屏（1600×2560 @2x = 800×1280dp）→ 仍是 pad', () {
      // 按**最短边**判定：设备形态与当前朝向无关，横竖都算平板。
      expect(
        formFactorForDisplay(
          physicalSize: const Size(1600, 2560),
          devicePixelRatio: 2.0,
        ),
        DeviceFormFactor.pad,
      );
    });

    test('断点边界：最短边恰好 600dp → pad（半开区间上界含）', () {
      expect(
        formFactorForDisplay(
          physicalSize: const Size(1200, 1600),
          devicePixelRatio: 2.0,
        ),
        DeviceFormFactor.pad,
      );
    });

    test('断点边界：最短边 599dp → phone', () {
      expect(
        formFactorForDisplay(
          physicalSize: const Size(1198, 1600),
          devicePixelRatio: 2.0,
        ),
        DeviceFormFactor.phone,
      );
    });

    test('尺寸未就绪（0×0）→ 回落 phone（安全侧）', () {
      // 误判成平板会让手机锁横屏（整机不可用）；误判成手机只是让平板晚一帧
      // 进横屏（可恢复）。两害相权取轻。
      expect(
        formFactorForDisplay(
          physicalSize: Size.zero,
          devicePixelRatio: 2.0,
        ),
        DeviceFormFactor.phone,
      );
    });

    test('像素比非法（0）→ 回落 phone，不除零', () {
      expect(
        formFactorForDisplay(
          physicalSize: const Size(2560, 1600),
          devicePixelRatio: 0,
        ),
        DeviceFormFactor.phone,
      );
    });

    test('平板被 letterbox 成竖条也判得对——判定源是显示屏而非窗口', () {
      // 回归：改造前按窗口尺寸判，平板被 letterbox 成 600×800dp 窗口时
      // 短边恰好 600 才侥幸判对，一旦塞得更窄就退回手机界面。
      // 这里直接以显示屏尺寸判定，与窗口形状无关。
      expect(
        formFactorForDisplay(
          physicalSize: const Size(2560, 1600),
          devicePixelRatio: 2.0,
        ),
        DeviceFormFactor.pad,
        reason: '窗口再窄也不影响：判定只看显示屏',
      );
    });
  });

  group('resolveStartupFormFactor：启动解析', () {
    // 注意：判定源是 `view.display`（显示屏），**不是** `view.physicalSize`
    // （窗口）。测试里必须设 `view.display.size`——只设 physicalSize 的话
    // display 仍是测试默认值，用例会因为默认值恰好也是 pad 而"假通过"。
    testWidgets('显示屏就绪 → 立刻按显示屏判定（本机 2560×1600 @2x = pad）', (tester) async {
      tester.view.display.size = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.display.resetSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      expect(await resolveStartupFormFactor(), DeviceFormFactor.pad);
    });

    testWidgets('手机尺寸的显示屏 → phone（证明读的确实是 display）', (tester) async {
      tester.view.display.size = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.display.resetSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      expect(await resolveStartupFormFactor(), DeviceFormFactor.phone);
    });

    testWidgets('显示屏未就绪 → 等超时后回落 phone（不永久挂起）', (tester) async {
      tester.view.display.size = Size.zero;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.display.resetSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // runAsync：轮询等的是真实时间，widget 测试默认的 FakeAsync 里
      // Future.delayed 永远不会到期，直接 await 会挂到超时。
      final factor = await tester.runAsync(
        () => resolveStartupFormFactor(
          timeout: const Duration(milliseconds: 60),
        ),
      );
      expect(factor, DeviceFormFactor.phone);
    });
  });

  test('formFactorProvider：未注入时取值立刻抛错，不静默给默认值', () {
    // 静默的默认值正是"平板跑成手机界面"这类问题最难查的地方——忘了注入
    // 就该在启动时炸掉，而不是悄悄按某个形态跑起来。
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container.read(formFactorProvider),
      throwsA(isA<StateError>()),
    );
  });

  test('formFactorProvider：注入后返回注入值（main() 的用法）', () {
    final container = ProviderContainer(
      overrides: [formFactorProvider.overrideWithValue(DeviceFormFactor.pad)],
    );
    addTearDown(container.dispose);

    expect(container.read(formFactorProvider), DeviceFormFactor.pad);
  });
}
