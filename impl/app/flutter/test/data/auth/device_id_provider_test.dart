import 'package:contexta/data/auth/device_id_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DeviceIdProvider 测试：首次生成（32 位 hex）+ 持久化复用。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('首次生成 32 位 hex 并持久化；再次读取返回同一 id', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = DeviceIdProvider();

    final first = await provider.getDeviceId();
    final second = await provider.getDeviceId();

    expect(first, second);
    expect(first, hasLength(32));
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(first), isTrue);
  });

  test('已有 device_id 时直接复用（不重新生成）', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'abc123'});
    final provider = DeviceIdProvider();

    expect(await provider.getDeviceId(), 'abc123');
  });
}
