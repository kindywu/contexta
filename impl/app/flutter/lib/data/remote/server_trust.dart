import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 内嵌自签名服务端证书（**证书钉扎**）——随 App 打包（pubspec `assets/certs/server.crt`）。
///
/// ⚠️ 与服务器 `/opt/contexta/server/certs/server.crt` 必须是同一份；换 IP / 重签后
/// 必须同步替换本文件并重新打包（否则握手即断，见 config-and-deploy.md §2.1）。
const serverCertAssetPath = 'assets/certs/server.crt';

/// 证书字节缓存：main() 启动时经 [loadServerTrustCert] 预载（rootBundle 是唯一
/// 可靠途径——debug 模式下 Flutter asset 不在文件系统里，直接按路径读会失败）。
Uint8List? _certBytes;

/// 内嵌证书的 DER（PEM 解析失败 → null，此时只剩信任锚链校验兜底）。
Uint8List? _certDer;

/// 启动时预载内嵌证书（幂等；失败仅告警——本地开发无证书场景允许缺省）。
Future<void> loadServerTrustCert() async {
  try {
    final bytes =
        (await rootBundle.load(serverCertAssetPath)).buffer.asUint8List();
    _certBytes = bytes;
    _certDer = pemToDer(utf8.decode(bytes));
  } catch (e) {
    debugPrint('[TLS] 内嵌服务端证书不可用，回退默认信任库: $e');
  }
}

/// PEM → DER（去掉 `-----` 头尾行、拼接 base64 后解码）。失败返回 null 并留日志。
@visibleForTesting
Uint8List? pemToDer(String pem) {
  try {
    final body = pem
        .split('\n')
        .where((l) => !l.contains('-----') && l.trim().isNotEmpty)
        .join();
    return base64Decode(body);
  } catch (e) {
    debugPrint('[TLS] 内嵌证书 PEM 解析失败: $e');
    return null;
  }
}

/// 为 Dio 装配「只信内嵌证书」的 HTTPS 适配器；证书未加载 → null（走默认信任库）。
///
/// 信任模型 = **证书钉扎**：对端证书 DER 与内嵌证书逐字节相同才放行（放行/拒绝都留日志）。
///
/// 为什么不再依赖 `SecurityContext.setTrustedCertificatesBytes`（信任锚）：
/// 2026-09-19 实测——**部分平台的 BoringSSL 不接受「自签叶子证书直接作信任锚」**：
/// 同一证书 curl/OpenSSL 校验通过、Android 端可过，但 iOS / 宿主 Dart 端握手报
/// `CERTIFICATE_VERIFY_FAILED: application verification failure(handshake.cc:320)`
/// （证书本身合规：SAN 含 IP、CA:TRUE、EKU 正确）。钉扎与平台校验实现无关，
/// 且比"信任链 + 系统根"更严格。信任锚上下文仍保留：能过链校验的平台多一层校验。
HttpClientAdapter? buildServerTrustAdapter() {
  final bytes = _certBytes;
  if (bytes == null) return null;
  final ctx = _buildTrustContext(bytes);
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient(context: ctx);
      client.badCertificateCallback = (cert, host, port) {
        final pinned = _certDer;
        if (pinned != null && _bytesEqual(cert.der, pinned)) {
          debugPrint('[TLS] 证书钉扎通过: ${cert.subject}');
          return true;
        }
        // 未钉扎：拒绝并留痕（不静默）
        debugPrint('[TLS] 拒绝未钉扎证书: subject=${cert.subject} '
            'issuer=${cert.issuer} sha1=${cert.sha1}');
        return false;
      };
      return client;
    },
  );
}

/// 只信任内嵌证书的 TLS 上下文（失败 → null，此时只靠钉扎）。
///
/// 必要性：Dart 的 TLS 栈（BoringSSL）**不读** Android network security config，
/// 仅靠 NSC 配置会 `CERTIFICATE_VERIFY_FAILED: self signed certificate`（2026-09-17 实测）。
SecurityContext? _buildTrustContext(Uint8List bytes) {
  try {
    return SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(bytes);
  } catch (e) {
    debugPrint('[TLS] 内嵌证书装入信任锚失败（改用钉扎）: $e');
    return null;
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
