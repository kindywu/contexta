import 'dart:io';

import 'package:contexta/core/platform/app_orientation.dart';
import 'package:contexta/core/platform/device_form_factor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 方向锁定测试：手机固定竖屏、平板固定横屏，**两档都不允许翻转**。
///
/// 分两层验证：Dart 侧向平台发出的方向请求（可 mock），以及原生侧配置文件
/// 里的声明（直接读文件——android/ 与 ios/ 被 analyzer 排除，没有别的手段
/// 能守住这两处）。
///
/// **形态判定本身**（显示屏尺寸 → phone/pad）在 `device_form_factor_test.dart`
/// 里测；本文件只测「形态 → 方向请求」的映射，判定与执行分开守。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  MethodCall orientationCall() => calls.singleWhere(
    (MethodCall c) => c.method == 'SystemChrome.setPreferredOrientations',
  );

  test('lockAppToPortrait：只请求 portraitUp（单元素 = 固定竖屏，不可翻转）', () async {
    await lockAppToPortrait();

    expect(orientationCall().arguments, <String>['DeviceOrientation.portraitUp']);
  });

  test('lockAppToLandscape：只请求 landscapeLeft（单元素 = 固定横屏，不可翻转）', () async {
    await lockAppToLandscape();

    // 关键：只要一个方向。传 [landscapeLeft, landscapeRight] 会映射为
    // userLandscape——跟随系统自动旋转，允许 180° 翻转，与设计不符。
    expect(
      orientationCall().arguments,
      <String>['DeviceOrientation.landscapeLeft'],
    );
  });

  group('applyOrientationPolicy：形态 → 方向', () {
    test('手机 → 锁 portraitUp', () async {
      await applyOrientationPolicy(DeviceFormFactor.phone);

      expect(orientationCall().arguments, <String>['DeviceOrientation.portraitUp']);
    });

    test('平板 → 锁单一横屏，永不为竖屏', () async {
      await applyOrientationPolicy(DeviceFormFactor.pad);

      expect(
        orientationCall().arguments,
        <String>['DeviceOrientation.landscapeLeft'],
      );
    });
  });

  group('原生侧方向声明', () {
    test('AndroidManifest：声明弹性窗口豁免，且**不写死** screenOrientation', () {
      final String manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      // Android 16（targetSdk ≥ 36）在 sw ≥ 600dp 大屏上默认忽略方向限制
      // （实测 ignoreOrientationRequest=true）——没有这条豁免，平板即使请求
      // 横屏也会被塞进竖屏窗口（两侧黑边）。见 docs/app-orientation.md。
      expect(
        manifest,
        contains('android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY'),
      );

      // 刻意不声明 screenOrientation：手机竖屏 / 平板横屏是**设备相关**的，
      // 写死在 manifest 里会让平板在引擎启动前就被锁成竖屏、闪一下竖屏黑边。
      // 方向统一由 Dart 侧按形态请求（applyOrientationPolicy）。
      expect(manifest, isNot(contains('android:screenOrientation')));
    });

    test('Info.plist：iPhone 只剩竖屏、iPad 只剩横屏，且 iPad 全屏固定', () {
      final String plist = File('ios/Runner/Info.plist').readAsStringSync();

      String orientationsFor(String key) {
        final int start = plist.indexOf('<key>$key</key>');
        expect(start, greaterThan(-1), reason: '缺 $key');
        final int end = plist.indexOf('</array>', start);
        return plist.substring(start, end);
      }

      final String iphone = orientationsFor('UISupportedInterfaceOrientations');
      expect(iphone, contains('UIInterfaceOrientationPortrait'));
      expect(iphone, isNot(contains('Landscape')));

      // iPad 与手机是两棵界面树，平板树按横屏设计（见 docs/adaptive-layout.md）
      final String ipad = orientationsFor('UISupportedInterfaceOrientations~ipad');
      expect(ipad, contains('UIInterfaceOrientationLandscapeLeft'));
      expect(ipad, isNot(contains('Portrait')));

      // iPadOS 把「支持多方向」的 App 视为可自由缩放，方向声明会被忽略；
      // 声明全屏固定后系统才维持横屏锁定（见 docs/app-orientation.md）。
      expect(plist, contains('<key>UIRequiresFullScreen</key>'));
    });

    test('Info.plist：声明后台同步任务标识（workmanager 在 iOS 的硬性要求）', () {
      final String plist = File('ios/Runner/Info.plist').readAsStringSync();

      // BGTaskScheduler 要求标识先声明在 BGTaskSchedulerPermittedIdentifiers，
      // 否则提交任务时直接断言崩溃（_handleSubmissionWithoutRegistration）。
      // 标识串必须与 sync_callback_dispatcher.dart 的 dailySyncTaskName 一致。
      expect(
        plist,
        contains('<key>BGTaskSchedulerPermittedIdentifiers</key>'),
      );
      expect(plist, contains('<string>dailyArticleSync</string>'));
      expect(plist, contains('<key>UIBackgroundModes</key>'));
    });
  });
}
