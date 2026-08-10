import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/platform/push_deep_links.dart';

void main() {
  group('isAllowedDeepLink', () {
    test('aceita rotas conhecidas do app', () {
      expect(isAllowedDeepLink('/'), isTrue);
      expect(isAllowedDeepLink('/transactions'), isTrue);
      expect(isAllowedDeepLink('/more/budget'), isTrue);
      expect(isAllowedDeepLink('/more/credit-cards/abc123-DEF'), isTrue);
    });

    test('aceita rotas conhecidas com query string simples', () {
      expect(
        isAllowedDeepLink('/transactions?openTransactionId=abc-123'),
        isTrue,
      );
    });

    test('rejeita rotas fora da lista de permissão', () {
      expect(isAllowedDeepLink('/admin'), isFalse);
      expect(isAllowedDeepLink('/more/login-data'), isFalse);
      expect(isAllowedDeepLink('https://evil.example.com'), isFalse);
      expect(isAllowedDeepLink('javascript:alert(1)'), isFalse);
    });

    test('rejeita query string com caracteres perigosos', () {
      expect(isAllowedDeepLink('/transactions?x=<script>'), isFalse);
      expect(isAllowedDeepLink('/transactions?x=a"b'), isFalse);
    });

    test('rejeita entradas malformadas', () {
      expect(isAllowedDeepLink(''), isFalse);
      expect(isAllowedDeepLink(null), isFalse);
      expect(isAllowedDeepLink('relative/path'), isFalse);
    });
  });
}
