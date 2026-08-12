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

class _RefreshFailureAdapter implements HttpClientAdapter {
  _RefreshFailureAdapter(this.statusCode);

  final int statusCode;
  int refreshCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/auth/refresh') {
      refreshCalls++;
      return ResponseBody.fromString(
        jsonEncode({
          'error': {'message': 'refresh indisponível'},
        }),
        statusCode,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    throw StateError('Chamada inesperada: ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}

String _jwtExpiringAt(DateTime expiresAt) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({'exp': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000}),
        ),
      )
      .replaceAll('=', '');
  return 'header.$payload.signature';
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
      // O token é renovado antes das chamadas protegidas, sem gastar duas
      // respostas 401 para descobrir que ele expirou.
      expect(adapter.protectedCalls, 2);
      expect(await storage.read(key: 'hopecash_access_token'), 'fresh-access');
      expect(await storage.read(key: 'hopecash_refresh_token'), 'refresh-2');
    },
  );

  test(
    'preserva a sessão quando o refresh falha por erro transitório',
    () async {
      final expired = _jwtExpiringAt(
        DateTime.now().subtract(const Duration(minutes: 5)),
      );
      FlutterSecureStorage.setMockInitialValues({
        'hopecash_access_token': expired,
        'hopecash_refresh_token': 'refresh-1',
        'hopecash_user': '{"id":"user-1"}',
      });
      const storage = FlutterSecureStorage();
      final adapter = _RefreshFailureAdapter(503);
      final refreshDio = Dio(
        BaseOptions(baseUrl: 'https://example.test/api/v1'),
      )..httpClientAdapter = adapter;
      var expiryNotifications = 0;
      final client = ApiClient(
        storage: storage,
        refreshDio: refreshDio,
        onSessionExpired: () => expiryNotifications++,
      );

      expect(await client.ensureSessionFresh(), isFalse);

      expect(adapter.refreshCalls, 1);
      expect(await storage.read(key: 'hopecash_access_token'), expired);
      expect(await storage.read(key: 'hopecash_refresh_token'), 'refresh-1');
      expect(await storage.read(key: 'hopecash_user'), isNotNull);
      expect(expiryNotifications, 0);
    },
  );

  test('encerra a sessão e notifica quando o refresh é rejeitado', () async {
    final expired = _jwtExpiringAt(
      DateTime.now().subtract(const Duration(minutes: 5)),
    );
    FlutterSecureStorage.setMockInitialValues({
      'hopecash_access_token': expired,
      'hopecash_refresh_token': 'refresh-revoked',
      'hopecash_user': '{"id":"user-1"}',
      'hopecash_acting': '{"owner_id":"owner-1"}',
    });
    const storage = FlutterSecureStorage();
    final adapter = _RefreshFailureAdapter(401);
    final refreshDio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
      ..httpClientAdapter = adapter;
    var expiryNotifications = 0;
    final client = ApiClient(
      storage: storage,
      refreshDio: refreshDio,
      onSessionExpired: () => expiryNotifications++,
    );

    expect(await client.ensureSessionFresh(), isFalse);

    expect(adapter.refreshCalls, 1);
    expect(await storage.read(key: 'hopecash_access_token'), isNull);
    expect(await storage.read(key: 'hopecash_refresh_token'), isNull);
    expect(await storage.read(key: 'hopecash_user'), isNull);
    expect(await storage.read(key: 'hopecash_acting'), isNull);
    expect(expiryNotifications, 1);

    // Novas chamadas não podem abrir várias navegações concorrentes para login.
    expect(await client.ensureSessionFresh(), isFalse);
    expect(expiryNotifications, 1);
  });

  test(
    'não renova um access token que ainda tem validade suficiente',
    () async {
      final valid = _jwtExpiringAt(
        DateTime.now().add(const Duration(minutes: 10)),
      );
      FlutterSecureStorage.setMockInitialValues({
        'hopecash_access_token': valid,
        'hopecash_refresh_token': 'refresh-1',
      });
      const storage = FlutterSecureStorage();
      final adapter = _RefreshFailureAdapter(500);
      final refreshDio = Dio(
        BaseOptions(baseUrl: 'https://example.test/api/v1'),
      )..httpClientAdapter = adapter;
      final client = ApiClient(storage: storage, refreshDio: refreshDio);

      expect(await client.ensureSessionFresh(), isTrue);
      expect(adapter.refreshCalls, 0);
    },
  );
}
