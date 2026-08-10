import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento simples de sessão (tokens/JSON do usuário).
///
/// Usa `shared_preferences` — no web isso é `localStorage`, que funciona em
/// contexto inseguro (HTTP em IP interno) e seguro (HTTPS). Evita a dependência
/// da Web Crypto API (`crypto.subtle`) do `flutter_secure_storage`, indisponível
/// fora de HTTPS/localhost. Mantém a mesma assinatura usada pelo ApiClient.
class TokenStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> read({required String key}) async => (await _prefs).getString(key);

  Future<void> write({required String key, required String value}) async =>
      (await _prefs).setString(key, value);

  Future<void> delete({required String key}) async => (await _prefs).remove(key);

  Future<void> deleteAll() async {
    final prefs = await _prefs;
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('hopecash_rtg_')) await prefs.remove(key);
    }
  }
}
