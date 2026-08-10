import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Notificação bancária capturada pelo serviço nativo Android.
class CapturedNotification {
  const CapturedNotification({
    required this.hash,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.postedAt,
  });

  final String hash;
  final String packageName;
  final String appName;
  final String title;
  final String text;
  final DateTime postedAt;

  static CapturedNotification? fromMap(Map<Object?, Object?> map) {
    final hash = map['hash'] as String?;
    if (hash == null || hash.isEmpty) return null;
    return CapturedNotification(
      hash: hash,
      packageName: map['package'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      text: map['text'] as String? ?? '',
      postedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['postedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Ponte com o listener nativo de notificações.
/// Fora do Android tudo é no-op seguro: [isSupported] = false, listas vazias.
class NotificationCapture {
  static const _channel = MethodChannel(
    'br.com.newhope.hopecash/notification_capture',
  );

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Se o usuário concedeu acesso às notificações nas configurações.
  Future<bool> isPermissionGranted() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isPermissionGranted') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Abre a tela do Android de acesso a notificações.
  Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // Sem tela de configuração disponível — nada a fazer.
    } on MissingPluginException {
      // Plataforma sem implementação nativa.
    }
  }

  /// Busca as notificações capturadas que ainda não foram processadas.
  Future<List<CapturedNotification>> fetchPending() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('fetchPending');
      return [
        for (final item in raw ?? const [])
          if (item is Map<Object?, Object?>)
            ?CapturedNotification.fromMap(item),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Remove da fila nativa notificações já processadas pelo Flutter.
  Future<void> markConsumed(List<String> hashes) async {
    if (!isSupported || hashes.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('markConsumed', {'hashes': hashes});
    } on PlatformException {
      // Fila será limpa na próxima tentativa.
    } on MissingPluginException {
      // Plataforma sem implementação nativa.
    }
  }
}
