import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/utils/voice_parse.dart';

void main() {
  const categories = [
    VoiceOption(id: 'cat-mercado', name: 'Mercado', type: 'expense'),
    VoiceOption(id: 'cat-salario', name: 'Salário', type: 'income'),
  ];
  const accounts = [VoiceOption(id: 'acc-1', name: 'Corrente')];
  const cards = [VoiceOption(id: 'card-1', name: 'Nubank')];

  group('parseVoiceLocally', () {
    test('extrai valor, cartão, parcelas e categoria de uma despesa', () {
      final r = parseVoiceLocally(
        'gastei 45,50 no mercado ontem no Nubank em 3 vezes',
        categories: categories,
        accounts: accounts,
        cards: cards,
        now: DateTime(2026, 7, 5),
      );
      expect(r.type, 'expense');
      expect(r.amount, 45.50);
      expect(r.cardId, 'card-1');
      expect(r.accountId, isNull);
      expect(r.installments, 3);
      expect(r.categoryId, 'cat-mercado');
      expect(r.date, '2026-07-04'); // ontem
      expect(r.paid, isTrue);
      expect(r.source, 'local');
    });

    test('reconhece receita e ignora cartão/categoria de despesa', () {
      final r = parseVoiceLocally(
        'recebi 5000 de salário na corrente',
        categories: categories,
        accounts: accounts,
        cards: cards,
      );
      expect(r.type, 'income');
      expect(r.amount, 5000);
      expect(r.categoryId, 'cat-salario');
      expect(r.accountId, 'acc-1');
      expect(r.cardId, isNull);
    });

    test('sem valor reconhecível devolve amount nulo e mantém a frase', () {
      final r = parseVoiceLocally('compra da farmácia');
      expect(r.amount, isNull);
      expect(r.description, isNotEmpty);
      expect(r.type, 'expense');
    });

    test('marca como previsto quando a fala indica pagamento futuro', () {
      final r = parseVoiceLocally('vou pagar 200 reais de luz');
      expect(r.paid, isFalse);
      expect(r.amount, 200);
    });
  });

  group('valores por extenso', () {
    test('reais e centavos falados: "cem reais e vinte" = 100,20', () {
      final r = parseVoiceLocally(
        'gastei cem reais e vinte no débito na farmácia',
      );
      expect(r.type, 'expense');
      expect(r.amount, 100.20);
      expect(r.description.toLowerCase(), contains('farmácia'));
      expect(r.description.toLowerCase(), isNot(contains('débito')));
      expect(r.description.toLowerCase(), isNot(contains('cem')));
    });

    test('composição por extenso: "cento e cinquenta reais" = 150', () {
      final r = parseVoiceLocally(
        'paguei cento e cinquenta reais no mercado',
        categories: categories,
      );
      expect(r.amount, 150);
      expect(r.categoryId, 'cat-mercado');
    });

    test('milhares: "mil e duzentos" = 1200 como receita', () {
      final r = parseVoiceLocally(
        'recebi mil e duzentos de salário',
        categories: categories,
      );
      expect(r.type, 'income');
      expect(r.amount, 1200);
      expect(r.categoryId, 'cat-salario');
    });

    test('centavos com dígitos após "reais": "45 reais e 90" = 45,90', () {
      final r = parseVoiceLocally('gastei 45 reais e 90 no posto');
      expect(r.amount, 45.90);
    });

    test('centavos explícitos: "dois reais e cinquenta centavos" = 2,50', () {
      final r = parseVoiceLocally(
        'gastei dois reais e cinquenta centavos na padaria',
      );
      expect(r.amount, 2.50);
    });

    test('apenas centavos: "cinquenta centavos" = 0,50', () {
      final r = parseVoiceLocally('gastei cinquenta centavos na bala');
      expect(r.amount, 0.50);
    });

    test('não confunde parcelas com valor: "em tres vezes"', () {
      final r = parseVoiceLocally(
        'gastei cem reais no mercado em tres vezes no Nubank',
        categories: categories,
        cards: cards,
      );
      expect(r.amount, 100);
      expect(r.installments, 3);
      expect(r.cardId, 'card-1');
    });

    test('"vinte e cinco reais" junta dezena e unidade = 25', () {
      final r = parseVoiceLocally(
        'paguei vinte e cinco reais de estacionamento',
      );
      expect(r.amount, 25);
    });

    test('"dois mil e trezentos reais" = 2300', () {
      final r = parseVoiceLocally('recebi dois mil e trezentos reais');
      expect(r.amount, 2300);
    });
  });
}
