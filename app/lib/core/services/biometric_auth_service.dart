import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Autenticação local (biometria) para proteger a sessão persistida no
/// aparelho. Tolerante a falhas por design: plataforma sem suporte (web,
/// desktop sem sensor, biometria não cadastrada) simplesmente não usa a
/// trava e o app abre direto, como antes.
class BiometricAuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Há biometria pronta para uso (hardware + digital/rosto cadastrado)?
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Pede a biometria. O próprio sistema pode oferecer a credencial do
  /// aparelho (PIN/padrão) como alternativa após falhas.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
