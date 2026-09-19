import 'dart:convert';
import 'dart:typed_data';

import 'package:contexta/data/remote/auth_api.dart';
import 'package:contexta/data/remote/dto/session_device_dto.dart';
import 'package:contexta/data/remote/server_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options) handler = _unset;
  RequestOptions? lastRequest;
  static Future<ResponseBody> _unset(RequestOptions _) =>
      throw StateError('stub adapter: handler 未设置');
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? s, Future<void>? c) async {
    lastRequest = options;
    return handler(options);
  }
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int statusCode, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {Headers.contentTypeHeader: ['application/json; charset=utf-8']},
    );

void main() {
  late _StubAdapter adapter;
  late AuthApi api;

  setUp(() {
    adapter = _StubAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    api = AuthApi(ServerApiClient(dio,
        baseUrl: 'https://api.example.com', tokenProvider: () async => null));
  });

  test('previewLogin 解析 evicted（含机型与毫秒时间）', () async {
    adapter.handler = (_) async => _json(200, {
          'code': 0,
          'data': {
            'evicted': [
              {
                'device_id': 'abc12345',
                'device_name': 'Xiaomi 14',
                'issued_at': 1758000000000,
                'last_active_at': 1758000000000,
              }
            ]
          }
        });
    final result = await api.previewLogin(phone: '13800000000', deviceId: 'me');
    expect(result.evicted, hasLength(1));
    expect(result.evicted.first.deviceId, 'abc12345');
    expect(result.evicted.first.deviceName, 'Xiaomi 14');
    expect(result.evicted.first.issuedAtMillis, 1758000000000);
    expect(adapter.lastRequest!.uri.path, '/api/auth/login/preview');
    expect(adapter.lastRequest!.data, {'phone': '13800000000', 'device_id': 'me'});
  });

  test('previewLogin 空列表', () async {
    adapter.handler = (_) async => _json(200, {'code': 0, 'data': {'evicted': []}});
    expect((await api.previewLogin(phone: '13800000000', deviceId: 'me')).evicted, isEmpty);
  });

  test('login 解析 evicted 与 device_name（可空）', () async {
    adapter.handler = (_) async => _json(200, {
          'code': 0,
          'data': {
            'token': 'tok',
            'expires_at': 9999999999,
            'evicted': [
              {'device_id': 'old1', 'device_name': null, 'issued_at': 1758000000000}
            ]
          }
        });
    final result = await api.login(phone: '13800000000', deviceId: 'me', deviceName: 'iPad');
    expect(result.evicted.single.deviceName, isNull);
    expect(adapter.lastRequest!.data,
        {'phone': '13800000000', 'device_id': 'me', 'device_name': 'iPad'});
  });

  test('deviceLabel：机型缺失用「未知设备」，短码取后 4 位', () {
    expect(deviceLabel('Xiaomi 14', 'abcdef123456'), 'Xiaomi 14 · 3456');
    expect(deviceLabel(null, 'abcdef123456'), '未知设备 · 3456');
    expect(deviceLabel('iPad', 'ab'), 'iPad · ab');
  });
}
