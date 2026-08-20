import 'dart:convert';
import 'dart:io';

import 'package:contexta/data/tts/kitten_tts_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// installModelAssets 测试：marker 语义 = marker 存在 && 期望文件齐全。
///
/// 回归背景：词典（en_rules/en_list）打包进 assets 后，旧 APK 留下的
/// .installed marker 会让新代码跳过拷贝 → CEPhonemizer 静默降级为纯规则
/// 音素器（音质变差）。修复后 marker 不再是跳过拷贝的充分条件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectedFiles = [
    'kitten_tts_micro_v0_8.onnx',
    'voices.npz',
    'en_rules',
    'en_list',
  ];

  late Directory tempRoot;
  late _MemoryBundle bundle;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('install_model_assets_test');
    bundle = _MemoryBundle();
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  /// 在临时根目录下执行安装，返回 models 目录。
  Future<void> install() => installModelAssets(
        'assets/kittentts_models',
        basePathOverride: tempRoot,
        bundleOverride: bundle,
      );

  test('全新目录：解压全部资产并写入 marker', () async {
    await install();

    for (final name in expectedFiles) {
      expect(File('${tempRoot.path}/models/$name').existsSync(), isTrue,
          reason: '$name 应被解压');
    }
    expect(File('${tempRoot.path}/models/.installed').existsSync(), isTrue);
  });

  test('stale marker（缺词典）：补齐缺失文件', () async {
    final models = Directory('${tempRoot.path}/models')
      ..createSync(recursive: true);
    File('${models.path}/.installed').writeAsStringSync('1');
    File('${models.path}/kitten_tts_micro_v0_8.onnx').writeAsBytesSync([1]);
    File('${models.path}/voices.npz').writeAsBytesSync([2]);

    await install();

    for (final name in expectedFiles) {
      expect(File('${tempRoot.path}/models/$name').existsSync(), isTrue,
          reason: '旧 marker 存在但词典缺失时应补齐 $name');
    }
  });

  test('marker 存在且文件齐全：跳过拷贝', () async {
    final models = Directory('${tempRoot.path}/models')
      ..createSync(recursive: true);
    File('${models.path}/.installed').writeAsStringSync('1');
    for (final name in expectedFiles) {
      File('${models.path}/$name').writeAsBytesSync([1]);
    }

    await install();

    expect(bundle.loadedKeys, isEmpty, reason: '文件齐全时不应触碰资产包');
  });
}

/// 内存 AssetBundle：记录 load 调用，返回占位字节。
class _MemoryBundle extends AssetBundle {
  final List<String> loadedKeys = [];

  @override
  Future<ByteData> load(String key) async {
    loadedKeys.add(key);
    final bytes = Uint8List.fromList(utf8.encode(key));
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      throw UnimplementedError();
}
