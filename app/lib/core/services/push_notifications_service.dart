import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/repositories/push_notifications_repository.dart';
import '../config/app_config.dart';
import '../platform/push_deep_links.dart';

/// Canal padrão de notificações no Android — precisa bater com o
/// `channelId` usado pelo backend (`FirebasePushProvider`).
const _androidChannel = AndroidNotificationChannel(
  'hopecash_default',
  'HopeCash',
  description: 'Avisos de vencimento, dicas e novidades do HopeCash',
  importance: Importance.high,
);

/// Handler de mensagens com o app em segundo plano/encerrado — precisa ser uma
/// função top-level (o plugin roda isso em um isolate próprio no Android).
/// Mensagens com bloco "notification" já são exibidas pelo sistema
/// operacional sozinho nesse estado; não há nada a fazer aqui além de
/// existir para satisfazer o registro exigido pelo plugin.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Integração com o Firebase Cloud Messaging: inicialização, permissão,
/// ciclo de vida do token e apresentação/abertura de notificações.
///
/// Nunca interfere com a captura local de notificações bancárias
/// ([NotificationCapture]/`BankNotificationListenerService`) — são
/// mecanismos completamente independentes (push via FCM × leitura local de
/// notificações de apps de banco), com canais/plugins próprios.
class PushNotificationsService {
  PushNotificationsService(this._repository);

  final PushNotificationsRepository _repository;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  String? _registeredToken;
  String? _lastHandledMessageId;
  bool _initialized = false;
  void Function(String deepLink)? _onDeepLink;

  /// No Web/PWA o Firebase precisa de configuração explícita (sem arquivo
  /// nativo) — se as chaves não foram informadas no build, o push fica
  /// desabilitado nessa plataforma, mas o resto do app funciona normalmente.
  bool get isSupported => kIsWeb ? AppConfig.firebaseWebConfigured : true;

  bool get isInitialized => _initialized;

  /// Inicializa o Firebase e os listeners. Idempotente. [onDeepLink] é
  /// chamado quando o usuário toca numa notificação com um link interno
  /// válido, com o app em primeiro plano, segundo plano ou encerrado.
  Future<void> initialize({required void Function(String) onDeepLink}) async {
    _onDeepLink = onDeepLink;
    if (_initialized || !isSupported) return;

    try {
      await Firebase.initializeApp(options: kIsWeb ? _webOptions : null);
    } catch (err) {
      // Sem os arquivos/config nativos ainda (ex.: ambiente de desenvolvimento
      // incompleto) — o app segue funcionando normalmente sem push.
      return;
    }
    _initialized = true;

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      // Evita o banner nativo duplicado do iOS em primeiro plano — a exibição
      // passa a ser só via flutter_local_notifications, igual no Android.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    }
    await _setupLocalNotifications();

    _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleOpenedMessage(initialMessage);
  }

  FirebaseOptions get _webOptions => FirebaseOptions(
    apiKey: AppConfig.firebaseWebApiKey,
    appId: AppConfig.firebaseWebAppId,
    messagingSenderId: AppConfig.firebaseMessagingSenderId,
    projectId: AppConfig.firebaseProjectId,
    storageBucket: AppConfig.firebaseStorageBucket,
    authDomain: AppConfig.firebaseWebAuthDomain,
  );

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final link = response.payload;
        if (link != null && isAllowedDeepLink(link)) _onDeepLink?.call(link);
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  /// Pede a permissão do sistema e, se concedida, registra o token atual.
  /// Retorna `false` quando o usuário nega — o chamador decide como reagir
  /// (o serviço nunca insiste sozinho).
  Future<bool> requestPermissionAndRegister({
    String? installId,
    String? appVersion,
    String? locale,
    String? timezone,
  }) async {
    if (!_initialized) return false;
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted = _isGranted(settings);
    if (!granted) return false;
    await ensureRegistered(
      installId: installId,
      appVersion: appVersion,
      locale: locale,
      timezone: timezone,
    );
    return true;
  }

  /// Reconcilia o registro do token — chame no boot e ao retomar o app.
  /// Não solicita permissão de novo: só reafirma o token se a permissão já
  /// havia sido concedida antes. O registro no backend é idempotente, então
  /// é seguro (e recomendado) chamar isto sempre que houver conectividade.
  Future<void> ensureRegistered({
    String? installId,
    String? appVersion,
    String? locale,
    String? timezone,
  }) async {
    if (!_initialized) return;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (!_isGranted(settings)) return;

    try {
      final token = kIsWeb
          ? await FirebaseMessaging.instance.getToken(
              vapidKey: AppConfig.firebaseVapidKey,
            )
          : await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _registerToken(
          token,
          installId: installId,
          appVersion: appVersion,
          locale: locale,
          timezone: timezone,
        );
      }
      _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (newToken) => _registerToken(
          newToken,
          installId: installId,
          appVersion: appVersion,
          locale: locale,
          timezone: timezone,
        ),
      );
    } catch (_) {
      // Sem conexão agora — a próxima chamada (próximo boot/resume) tenta de novo.
    }
  }

  bool _isGranted(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  Future<void> _registerToken(
    String token, {
    String? installId,
    String? appVersion,
    String? locale,
    String? timezone,
  }) async {
    if (_registeredToken == token) return; // já registrado — evita chamadas repetidas
    try {
      await _repository.registerDevice(
        token: token,
        platform: _platformName,
        installId: installId,
        appVersion: appVersion,
        locale: locale,
        timezone: timezone,
      );
      _registeredToken = token;
    } catch (_) {
      // Falha de rede/servidor — não derruba o app; tentaremos de novo depois.
    }
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'web',
    };
  }

  /// Chame no logout, antes de limpar a sessão local — desativa o token no backend.
  Future<void> deactivateCurrentDevice() async {
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null || !_initialized) return;
    try {
      await _repository.deactivateDevice(token);
    } catch (_) {
      // Best-effort — na pior hipótese o token só fica inativo no próximo envio.
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (!_shouldProcess(message)) return;
    final notification = message.notification;
    if (notification == null) return;
    final deepLink = message.data['deep_link'];
    unawaited(
      _localNotifications.show(
        id: message.hashCode & 0x7fffffff,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'hopecash_default',
            'HopeCash',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: deepLink,
      ),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    if (!_shouldProcess(message)) return;
    final link = message.data['deep_link'];
    if (link != null && isAllowedDeepLink(link)) _onDeepLink?.call(link);
  }

  /// Evita processar a mesma mensagem duas vezes — por exemplo,
  /// `getInitialMessage()` seguido de um `onMessageOpenedApp` seria disparado
  /// para o mesmo toque em algumas versões de Android/iOS.
  bool _shouldProcess(RemoteMessage message) {
    final id = message.messageId;
    if (id != null && id == _lastHandledMessageId) return false;
    _lastHandledMessageId = id;
    return true;
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedAppSub?.cancel();
  }
}
