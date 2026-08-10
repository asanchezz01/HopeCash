import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/utils/finance_calc.dart';

void main() {
  group('monthsBetween', () {
    test('conta meses inteiros', () {
      expect(monthsBetween('2026-07-04', '2027-07-04'), 12);
      expect(monthsBetween('2026-07-04', '2026-10-01'), 3);
      expect(monthsBetween('2026-07-04', '2026-07-30'), 0);
    });

    test('não retorna negativo', () {
      expect(monthsBetween('2026-07-04', '2026-01-01'), 0);
    });
  });

  group('monthlyContributionNeeded', () {
    test('divide o restante pelos meses até a data alvo', () {
      expect(
        monthlyContributionNeeded(
          targetAmount: 12000,
          accumulatedAmount: 2000,
          targetDateIso: '2027-07-04',
          nowIso: '2026-07-04',
        ),
        833.33,
      );
    });

    test('meta atingida ou sem data → null', () {
      expect(
        monthlyContributionNeeded(
          targetAmount: 1000,
          accumulatedAmount: 1500,
          targetDateIso: '2027-01-01',
          nowIso: '2026-07-04',
        ),
        isNull,
      );
      expect(
        monthlyContributionNeeded(
          targetAmount: 1000,
          accumulatedAmount: 0,
          targetDateIso: null,
        ),
        isNull,
      );
    });

    test('data alvo já passada → valor restante integral', () {
      expect(
        monthlyContributionNeeded(
          targetAmount: 1000,
          accumulatedAmount: 400,
          targetDateIso: '2026-06-01',
          nowIso: '2026-07-04',
        ),
        600,
      );
    });
  });

  group('profitabilityPercent', () {
    test('calcula percentual sobre o aplicado', () {
      expect(profitabilityPercent(1000, 1100), 10);
      expect(profitabilityPercent(1000, 900), -10);
      expect(profitabilityPercent(0, 500), isNull);
    });
  });

  group('investmentValueHistory', () {
    test('gera 6 pontos e o último sempre bate com o saldo atual', () {
      final points = investmentValueHistory(
        currentTotal: 10000,
        movements: const [],
        nowIso: '2026-07-16',
      );
      expect(points.length, 6);
      expect(points.first.monthIso, '2026-02-01');
      expect(points.last.monthIso, '2026-07-01');
      expect(points.last.balance, 10000);
    });

    test('reconstrói o saldo passado subtraindo o efeito das movimentações', () {
      final points = investmentValueHistory(
        currentTotal: 1300,
        movements: const [
          (type: 'deposit', amount: 1000.0, movementDate: '2026-05-10'),
          (type: 'yield', amount: 100.0, movementDate: '2026-06-05'),
          (type: 'withdrawal', amount: 200.0, movementDate: '2026-07-01'),
        ],
        nowIso: '2026-07-16',
      );
      final april = points.firstWhere((p) => p.monthIso == '2026-04-01');
      final may = points.firstWhere((p) => p.monthIso == '2026-05-01');
      expect(april.balance, 400); // antes de qualquer movimentação
      expect(may.balance, 1400); // após o aporte de maio
      expect(may.deposits, 1000);
      expect(points.last.balance, 1300);
      expect(points.last.withdrawals, 200);
    });
  });

  group('addMonthsIso', () {
    test('soma meses preservando o dia', () {
      expect(addMonthsIso('2026-07-04', 1), '2026-08-04');
      expect(addMonthsIso('2026-11-15', 3), '2027-02-15');
    });

    test('ajusta para o último dia do mês quando necessário', () {
      expect(addMonthsIso('2026-01-31', 1), '2026-02-28');
      expect(addMonthsIso('2026-08-31', 1), '2026-09-30');
    });
  });

  group('cardDueDate', () {
    // Cartão fecha dia 28 e vence dia 8 do mês seguinte.
    test('compra antes do fechamento entra na fatura do mês', () {
      expect(
        cardDueDate(purchaseDate: '2026-07-10', closingDay: 28, dueDay: 8),
        '2026-08-08',
      );
    });

    test('compra após o fechamento vai para a próxima fatura', () {
      expect(
        cardDueDate(purchaseDate: '2026-07-29', closingDay: 28, dueDay: 8),
        '2026-09-08',
      );
    });

    test('vencimento no mesmo mês quando dueDay > closingDay', () {
      // Fecha dia 5, vence dia 15 do mesmo mês.
      expect(
        cardDueDate(purchaseDate: '2026-07-03', closingDay: 5, dueDay: 15),
        '2026-07-15',
      );
      expect(
        cardDueDate(purchaseDate: '2026-07-10', closingDay: 5, dueDay: 15),
        '2026-08-15',
      );
    });

    test('vira o ano corretamente', () {
      expect(
        cardDueDate(purchaseDate: '2026-12-30', closingDay: 28, dueDay: 8),
        '2027-02-08',
      );
    });
  });

  group('clampProgress', () {
    test('limita entre 0 e 1', () {
      expect(clampProgress(50, 100), 0.5);
      expect(clampProgress(150, 100), 1);
      expect(clampProgress(10, 0), 0);
    });
  });
}
