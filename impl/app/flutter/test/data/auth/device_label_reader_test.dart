import 'package:contexta/data/auth/device_label_reader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('contexta/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('返回原生机型名', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getDeviceLabel');
      return 'Xiaomi 14';
    });
    expect(await DeviceLabelReader().readDeviceLabel(), 'Xiaomi 14');
  });

  test('原生抛 PlatformException → null（降级未知设备）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'ERR');
    });
    expect(await DeviceLabelReader().readDeviceLabel(), isNull);
  });

  test('无插件实现（MissingPluginException）→ null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await DeviceLabelReader().readDeviceLabel(), isNull);
  });

  test('原生返回空串 → null（等同未知设备）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => '');
    expect(await DeviceLabelReader().readDeviceLabel(), isNull);
  });
}
