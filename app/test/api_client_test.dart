import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/data/remote/api_client.dart';

class _RotatingTokenAdapter implements HttpClientAdapter {
  int refreshCalls = 0;
  int protectedCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/auth/refresh') {
      refreshCalls++;
      // Mantém a renovação em voo para as duas respostas 401 se encontrarem.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return _jsonResponse({
        'data': {'access_token': 'fresh-access', 'refresh_token': 'refresh-2'},
      });
    }

    protectedCalls++;
    if (options.headers['Authorization'] == 'Bearer fresh-access') {
      return _jsonResponse({
        'data': {'ok': true},
      });
    }
    return _jsonResponse({
      'error': {'message': 'Token inválido'},
    }, statusCode: 401);
  }

  ResponseBody _jsonResponse(
    Map<String, dynamic> body, {
    int statusCode = 200,
  }) => ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'serializa refreshes concorrentes e repete ambas as requisições',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'hopecash_access_token': 'expired-access',
        'hopecash_refresh_token': 'refresh-1',
      });
      const storage = FlutterSecureStorage();
      final adapter = _RotatingTokenAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
        ..httpClientAdapter = adapter;
      final refreshDio = Dio(
        BaseOptions(baseUrl: 'https://example.test/api/v1'),
      )..httpClientAdapter = adapter;
      final client = ApiClient(
        storage: storage,
        dio: dio,
        refreshDio: refreshDio,
      );

      final responses = await Future.wait([
        client.dio.get('/first'),
        client.dio.get('/second'),
      ]);

      expect(
        responses.map((response) => response.statusCode),
        everyElement(200),
      );
      expect(adapter.refreshCalls, 1);
      expect(adapter.protectedCalls, 4);
      expect(await storage.read(key: 'hopecash_access_token'), 'fresh-access');
      expect(await storage.read(key: 'hopecash_refresh_token'), 'refresh-2');
    },
  );
}
