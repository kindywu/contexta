import 'dart:io';

import 'package:contexta/core/platform/app_orientation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 全局竖屏锁定测试。
///
/// 分两层验证：Dart 侧向平台发出的方向请求（可 mock），以及原生侧
/// 配置文件里的声明（直接读文件——android/ 与 ios/ 被 analyzer 排除，
/// 没有别的手段能守住这两处）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('lockAppToPortrait：只请求 portraitUp，不含任何横屏方向', () async {
    await lockAppToPortrait();

    final MethodCall call = calls.singleWhere((MethodCall c) =>
        c.method == 'SystemChrome.setPreferredOrientations');
    expect(call.arguments, <String>['DeviceOrientation.portraitUp']);
  });

  group('applyOrientationPolicy：按窗口尺寸分档', () {
    // 实测背景：小米 HyperOS（Android 16 / targetSdk 36 / sw813dp）**未**启用
    // 「大屏忽略方向声明」，manifest 声明 portrait 时窗口会被 letterbox 成
    // 666×813dp——平板侧必须显式请求 unspecified 才能横屏铺满。
    MethodCall orientationCall() => calls.singleWhere(
          (MethodCall c) => c.method == 'SystemChrome.setPreferredOrientations',
        );

    testWidgets('手机（最短边 360dp）→ 锁 portraitUp', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await applyOrientationPolicy();

      expect(orientationCall().arguments, <String>['DeviceOrientation.portraitUp']);
    });

    testWidgets('平板横屏（1219×813dp）→ 请求四方向（fullUser），窗口才铺得满',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(2438, 1626);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await applyOrientationPolicy();

      // 必须是显式四方向：空列表映射为 unspecified，会回落到 manifest 的
      // portrait，窗口继续被 letterbox（真机实测踩过）
      expect(orientationCall().arguments, <String>[
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
    });

    testWidgets('平板竖屏（813×1219dp）→ 同样四方向（横竖屏都可）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1626, 2438);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await applyOrientationPolicy();

      expect(orientationCall().arguments, hasLength(4));
    });
  });

  group('原生侧方向声明', () {
    test('AndroidManifest：刻意不声明固定方向，且显式可调整大小', () {
      // 2026-09-17 真机实测：小米 HyperOS（Android 16 / targetSdk 36）未启用
      // 「大屏忽略方向声明」的官方行为——manifest 只要声明 portrait（即使同时
      // 声明 resizeableActivity=true），pad 窗口就被 letterbox 成 666×813dp，
      // 永远进不了书页模式。故原生侧不声明方向，手机竖屏改由 Dart 侧保证。
      final String manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, isNot(contains('android:screenOrientation=')));
      expect(manifest, contains('android:resizeableActivity="true"'));
    });

    test('Info.plist：iPhone 支持方向只剩竖屏（iPad 不受限）', () {
      final String plist = File('ios/Runner/Info.plist').readAsStringSync();
      final int start = plist.indexOf('<key>UISupportedInterfaceOrientations</key>');
      final int end = plist.indexOf('</array>', start);
      expect(start, greaterThan(-1), reason: '缺 UISupportedInterfaceOrientations');
      final String iphone = plist.substring(start, end);
      expect(iphone, contains('UIInterfaceOrientationPortrait'));
      expect(iphone, isNot(contains('Landscape')));
    });
  });
}
