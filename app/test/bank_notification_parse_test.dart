import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/utils/bank_notification_parse.dart';
import 'package:hopecash/core/utils/voice_parse.dart';

void main() {
  const accounts = [
    VoiceOption(id: 'acc-nubank', name: 'Nubank'),
    VoiceOption(id: 'acc-itau', name: 'Itaú'),
  ];
  const cards = [
    VoiceOption(id: 'card-nubank', name: 'Nubank'),
    VoiceOption(id: 'card-visa', name: 'Visa Gold'),
  ];

  group('parseBankNotification', () {
    test('compra aprovada no cartão com estabelecimento', () {
      final r = parseBankNotification(
        title: 'Nubank',
        text:
            'Compra aprovada no cartão final 1234 no valor de R\$ 45,90 '
            'em MERCADO X',
        appName: 'Nubank',
        accounts: accounts,
        cards: cards,
      );
      expect(r, isNotNull);
      expect(r!.eventType, BankEventType.cardPurchase);
      expect(r.transactionType, 'expense');
      expect(r.amount, 45.90);
      expect(r.description, contains('MERCADO X'));
      expect(r.cardId, 'card-nubank');
      expect(r.accountId, isNull);
      expect(r.confidence, greaterThanOrEqualTo(0.5));
    });

    test('pix recebido é crédito em conta', () {
      final r = parseBankNotification(
        title: 'Itaú',
        text: 'Pix recebido de JOAO no valor de R\$ 250,00',
        appName: 'Itaú',
        accounts: accounts,
        cards: cards,
      );
      expect(r, isNotNull);
      expect(r!.eventType, BankEventType.accountCredit);
      expect(r.transactionType, 'income');
      expect(r.amount, 250.00);
      expect(r.description, contains('JOAO'));
      expect(r.accountId, 'acc-itau');
      expect(r.cardId, isNull);
    });

    test('pagamento é débito em conta', () {
      final r = parseBankNotification(
        title: 'Banco',
        text: 'Você pagou R\$ 89,90 para NETFLIX',
      );
      expect(r, isNotNull);
      expect(r!.eventType, BankEventType.accountDebit);
      expect(r.transactionType, 'expense');
      expect(r.amount, 89.90);
      expect(r.description, contains('NETFLIX'));
    });

    test('transferência enviada com valor com milhar', () {
      final r = parseBankNotification(
        title: 'Banco',
        text: 'Transferência enviada de R\$ 1.200,00',
      );
      expect(r, isNotNull);
      expect(r!.eventType, BankEventType.accountDebit);
      expect(r.transactionType, 'expense');
      expect(r.amount, 1200.00);
    });

    test('estorno no cartão é crédito', () {
      final r = parseBankNotification(
        title: 'Cartão',
        text: 'Estorno de R\$ 35,00 no cartão',
        cards: cards,
      );
      expect(r, isNotNull);
      expect(r!.eventType, BankEventType.cardRefund);
      expect(r.transactionType, 'income');
      expect(r.amount, 35.00);
    });

    test('aceita formatos R\$123,45, 12,90 e 12.90', () {
      final grudado = parseBankNotification(
        title: 'Banco',
        text: 'Pix enviado de R\$123,45',
      );
      expect(grudado!.amount, 123.45);

      final virgula = parseBankNotification(
        title: 'Banco',
        text: 'Compra no débito de 12,90 em PADARIA',
      );
      expect(virgula!.amount, 12.90);

      final ponto = parseBankNotification(
        title: 'Banco',
        text: 'Compra no débito de 12.90 em PADARIA',
      );
      expect(ponto!.amount, 12.90);
    });

    test('notificação sem movimentação financeira retorna null', () {
      final propaganda = parseBankNotification(
        title: 'Banco',
        text: 'Conheça o novo empréstimo consignado com taxas especiais',
      );
      expect(propaganda, isNull);

      final semValor = parseBankNotification(
        title: 'Banco',
        text: 'Pix recebido',
      );
      expect(semValor, isNull);
    });

    test('depósito e salário são créditos em conta', () {
      final deposito = parseBankNotification(
        title: 'Banco',
        text: 'Depósito de R\$ 500,00 na sua conta',
      );
      expect(deposito!.eventType, BankEventType.accountCredit);
      expect(deposito.transactionType, 'income');

      final salario = parseBankNotification(
        title: 'Banco',
        text: 'Seu salário de R\$ 3.500,00 caiu na sua conta',
      );
      expect(salario!.amount, 3500.00);
      expect(salario.transactionType, 'income');
    });

    test('saque é débito em conta', () {
      final r = parseBankNotification(
        title: 'Banco',
        text: 'Saque de R\$ 200,00 realizado no caixa eletrônico',
      );
      expect(r!.eventType, BankEventType.accountDebit);
      expect(r.transactionType, 'expense');
    });
  });
}
