/// Cálculos financeiros puros (testáveis sem Flutter).
library;

/// Meses inteiros entre duas datas ISO (mínimo 0).
int monthsBetween(String fromIso, String toIso) {
  final from = DateTime.parse(fromIso);
  final to = DateTime.parse(toIso);
  final months = (to.year - from.year) * 12 + (to.month - from.month);
  return months < 0 ? 0 : months;
}

/// Aporte mensal necessário para atingir a meta até a data alvo.
/// Retorna null sem data alvo ou com a meta já atingida; se a data já passou,
/// retorna o valor restante integral.
double? monthlyContributionNeeded({
  required double targetAmount,
  required double accumulatedAmount,
  String? targetDateIso,
  String? nowIso,
}) {
  final remaining = targetAmount - accumulatedAmount;
  if (remaining <= 0) return null;
  if (targetDateIso == null) return null;
  final now = nowIso ?? DateTime.now().toIso8601String().substring(0, 10);
  final months = monthsBetween(now, targetDateIso);
  if (months == 0) return _round2(remaining);
  return _round2(remaining / months);
}

/// Rentabilidade percentual de um investimento (null se nada aplicado).
double? profitabilityPercent(double applied, double current) {
  if (applied <= 0) return null;
  return _round2((current - applied) / applied * 100);
}

/// Um ponto mensal na evolução do patrimônio investido: saldo reconstruído
/// ao final do mês e o total de aportes, resgates e rendimentos lançados
/// dentro dele.
class InvestmentMonthPoint {
  const InvestmentMonthPoint({
    required this.monthIso,
    required this.balance,
    required this.deposits,
    required this.withdrawals,
    required this.yields,
  });

  /// Primeiro dia do mês (YYYY-MM-01).
  final String monthIso;
  final double balance;
  final double deposits;
  final double withdrawals;
  final double yields;
}

/// Reconstrói a evolução do patrimônio total investido nos últimos [months]
/// meses a partir do saldo atual ([currentTotal]) e do histórico de
/// movimentações de todos os investimentos.
///
/// Usa a mesma regra do saldo de cada investimento (aporte e rendimento
/// somam, resgate subtrai) para "andar para trás" no tempo: o saldo ao final
/// de um mês é o saldo atual menos o efeito de tudo que aconteceu depois
/// dele. O último ponto sempre corresponde exatamente a [currentTotal].
List<InvestmentMonthPoint> investmentValueHistory({
  required double currentTotal,
  required List<({String type, double amount, String movementDate})>
  movements,
  String? nowIso,
  int months = 6,
}) {
  final now = nowIso == null ? DateTime.now() : DateTime.parse(nowIso);
  final currentMonthStart = DateTime(now.year, now.month, 1);
  final monthStarts = [
    for (var i = months - 1; i >= 0; i--)
      DateTime(currentMonthStart.year, currentMonthStart.month - i, 1),
  ];
  // Limite superior (exclusivo) de cada balde: início do mês seguinte,
  // exceto no balde atual, onde é "agora" — assim o último ponto bate com
  // currentTotal exatamente.
  final upperBounds = [
    for (var i = 0; i < months; i++)
      i == months - 1
          ? now
          : DateTime(monthStarts[i].year, monthStarts[i].month + 1, 1),
  ];

  double effectOf(String type, double amount) =>
      type == 'withdrawal' ? -amount : amount;

  final deposits = List<double>.filled(months, 0);
  final withdrawals = List<double>.filled(months, 0);
  final yields = List<double>.filled(months, 0);
  for (final m in movements) {
    final d = DateTime.parse(m.movementDate);
    final idx = monthStarts.indexWhere(
      (s) => s.year == d.year && s.month == d.month,
    );
    if (idx == -1) continue;
    switch (m.type) {
      case 'deposit':
        deposits[idx] += m.amount;
      case 'withdrawal':
        withdrawals[idx] += m.amount;
      case 'yield':
        yields[idx] += m.amount;
    }
  }

  return [
    for (var i = 0; i < months; i++)
      InvestmentMonthPoint(
        monthIso: _fmt(monthStarts[i]),
        balance: _round2(
          currentTotal -
              movements
                  .where(
                    (m) => !DateTime.parse(
                      m.movementDate,
                    ).isBefore(upperBounds[i]),
                  )
                  .fold<double>(
                    0,
                    (sum, m) => sum + effectOf(m.type, m.amount),
                  ),
        ),
        deposits: _round2(deposits[i]),
        withdrawals: _round2(withdrawals[i]),
        yields: _round2(yields[i]),
      ),
  ];
}

/// Progresso 0..1 limitado (para barras de progresso).
double clampProgress(double value, double total) {
  if (total <= 0) return 0;
  final p = value / total;
  return p < 0 ? 0 : (p > 1 ? 1 : p);
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Soma meses a uma data ISO, ajustando para o último dia do mês quando preciso.
String addMonthsIso(String iso, int months) {
  final d = DateTime.parse(iso);
  final firstOfTarget = DateTime(d.year, d.month + months, 1);
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  final day = d.day > lastDay ? lastDay : d.day;
  return _fmt(DateTime(firstOfTarget.year, firstOfTarget.month, day));
}

/// Vencimento da fatura que receberá uma compra no cartão.
///
/// Compras até o dia de fechamento entram na fatura do mês; depois dele,
/// na do mês seguinte. O vencimento cai no [dueDay] do mês do fechamento
/// quando `dueDay > closingDay`, senão no mês seguinte ao fechamento.
String cardDueDate({
  required String purchaseDate,
  required int closingDay,
  required int dueDay,
}) {
  final p = DateTime.parse(purchaseDate);
  var closingMonth = DateTime(p.year, p.month, 1);
  if (p.day > closingDay) {
    closingMonth = DateTime(p.year, p.month + 1, 1);
  }
  final dueMonth = dueDay > closingDay
      ? closingMonth
      : DateTime(closingMonth.year, closingMonth.month + 1, 1);
  final lastDay = DateTime(dueMonth.year, dueMonth.month + 1, 0).day;
  final day = dueDay > lastDay ? lastDay : dueDay;
  return _fmt(DateTime(dueMonth.year, dueMonth.month, day));
}

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
