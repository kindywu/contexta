import 'dart:io';

import 'package:contexta/data/remote/server_trust.dart';
import 'package:flutter_test/flutter_test.dart';

/// 证书钉扎素材的加载与解析（不触网）：内嵌 PEM → DER、适配器装配。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内嵌证书可载入，PEM → DER 解析成功（DER 以 SEQUENCE 0x30 开头）', () async {
    await loadServerTrustCert();
    final pem = File(serverCertAssetPath).readAsStringSync();
    final der = pemToDer(pem);
    expect(der, isNotNull);
    expect(der!.length, greaterThan(300)); // P-256 自签证书约 400 字节
    expect(der.first, 0x30);
  });

  test('畸形 PEM → null（降级不抛，留日志）', () {
    expect(pemToDer('not a pem'), isNull);
  });

  test('载入后能装配出 TLS 适配器（证书缺失时才为 null）', () async {
    await loadServerTrustCert();
    expect(buildServerTrustAdapter(), isNotNull);
  });
}
