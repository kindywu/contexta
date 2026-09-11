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

  group('原生侧竖屏声明', () {
    test('AndroidManifest：MainActivity 固定 portrait', () {
      final String manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:screenOrientation="portrait"'));
      expect(manifest, isNot(contains('android:screenOrientation="landscape"')));
      expect(manifest, isNot(contains('android:screenOrientation="sensor"')));
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
