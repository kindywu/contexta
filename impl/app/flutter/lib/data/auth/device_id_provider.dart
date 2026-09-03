import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 设备标识（服务端 device_id）：shared_preferences 持久化，首次生成后固定。
///
/// 生成规则：`DateTime.now().microsecondsSinceEpoch` 16 位 hex（补零）+
/// 16 位随机 hex = 32 位 hex（不引 uuid 包）。
class DeviceIdProvider {
  DeviceIdProvider([this._prefs]);

  static const _key = 'device_id';

  /// 用 legacy SharedPreferences（而非 Async 版）：测试经
  /// `SharedPreferences.setMockInitialValues` 直接可注入，无需单独设置
  /// AsyncPlatform 实例；本处只做一次低频读写，缓存开销可忽略。
  Future<SharedPreferences>? _prefsFuture;
  SharedPreferences? _prefs;

  Future<String> getDeviceId() async {
    final prefs = _prefs ??= await (_prefsFuture ??=
        SharedPreferences.getInstance());
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generate();
    await prefs.setString(_key, id);
    return id;
  }

  String _generate() {
    final microsHex =
        DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0');
    final random = Random();
    final randomHex =
        List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
    return '$microsHex$randomHex';
  }
}
