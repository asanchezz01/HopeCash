import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/utils/money.dart';

void main() {
  group('parseMoney', () {
    test('aceita formato brasileiro', () {
      expect(parseMoney('1.234,56'), 1234.56);
      expect(parseMoney('R\$ 10,00'), 10.0);
      expect(parseMoney('0,99'), 0.99);
    });

    test('aceita formato com ponto decimal', () {
      expect(parseMoney('1234.56'), 1234.56);
      expect(parseMoney('10'), 10.0);
    });

    test('aceita valores negativos', () {
      expect(parseMoney('-1.234,56'), -1234.56);
      expect(parseMoney('R\$ -50,00'), -50.0);
      expect(parseMoney('-10'), -10.0);
    });

    test('rejeita entradas inválidas', () {
      expect(parseMoney(''), isNull);
      expect(parseMoney('abc'), isNull);
    });
  });

  group('formatMoney', () {
    test('formata em reais pt-BR', () {
      final formatted = formatMoney(1234.5);
      expect(formatted, contains('1.234,50'));
      expect(formatted, contains('R\$'));
    });

    test('trata nulo como zero', () {
      expect(formatMoney(null), contains('0,00'));
    });
  });

  group('formatDate', () {
    test('converte ISO para dd/MM/yyyy', () {
      expect(formatDate('2026-07-04'), '04/07/2026');
      expect(formatDate(null), '');
    });
  });
}
