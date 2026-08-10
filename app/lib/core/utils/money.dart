import 'package:intl/intl.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Formata um valor em reais: 1234.5 → "R$ 1.234,50".
String formatMoney(num? value) => _currency.format(value ?? 0);

/// Converte entrada do usuário ("1.234,56", "1234.56", "R$ 10") em double.
/// Retorna null se não for um número válido.
double? parseMoney(String input) {
  var v = input.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (v.isEmpty) return null;
  // Formato brasileiro: pontos de milhar + vírgula decimal.
  if (RegExp(r',\d{1,2}$').hasMatch(v)) {
    v = v.replaceAll('.', '').replaceAll(',', '.');
  } else {
    v = v.replaceAll(',', '');
  }
  final parsed = double.tryParse(v);
  if (parsed == null) return null;
  return (parsed * 100).roundToDouble() / 100;
}

/// Rótulo de leitor de tela para um valor em reais.
///
/// "R$ 1.234,50" é lido caractere a caractere por leitores de tela ("erre
/// cifrão um ponto dois três quatro"). Esta versão soa como alguém falando:
/// "1.234 reais e 50 centavos".
String moneySemanticLabel(num? value, {bool negative = false}) {
  final amount = (value ?? 0).abs();
  final cents = (amount * 100).round();
  final whole = cents ~/ 100;
  final fraction = cents % 100;
  final wholeLabel = NumberFormat.decimalPattern('pt_BR').format(whole);
  final parts = <String>[
    if (negative) 'menos',
    wholeLabel,
    whole == 1 ? 'real' : 'reais',
    if (fraction > 0) ...['e', '$fraction', fraction == 1 ? 'centavo' : 'centavos'],
  ];
  return parts.join(' ');
}

/// Data de hoje no formato ISO (YYYY-MM-DD).
String todayIso() => DateTime.now().toIso8601String().substring(0, 10);

/// Formata data ISO para exibição: "2026-07-04" → "04/07/2026".
String formatDate(String? isoDate) {
  if (isoDate == null || isoDate.length < 10) return '';
  final d = isoDate.substring(0, 10).split('-');
  return '${d[2]}/${d[1]}/${d[0]}';
}
