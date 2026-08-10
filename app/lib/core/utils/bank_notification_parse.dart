import 'money.dart';
import 'voice_parse.dart' show VoiceOption;

/// Tipo de evento financeiro identificado em uma notificação bancária.
enum BankEventType {
  /// Débito em conta: Pix enviado, compra no débito, pagamento, saque…
  accountDebit,

  /// Crédito em conta: Pix recebido, depósito, TED recebida, salário…
  accountCredit,

  /// Compra no cartão de crédito.
  cardPurchase,

  /// Estorno/crédito no cartão.
  cardRefund,
}

/// Resultado do parser local de notificações bancárias.
/// Nunca vira lançamento automaticamente — apenas sugestão para revisão.
class BankNotificationParseResult {
  const BankNotificationParseResult({
    required this.eventType,
    required this.transactionType,
    this.amount,
    required this.description,
    this.accountId,
    this.cardId,
    required this.confidence,
  });

  final BankEventType eventType;

  /// income | expense
  final String transactionType;
  final double? amount;
  final String description;

  /// Conta/cartão do usuário casados por nome/banco no texto, quando possível.
  final String? accountId;
  final String? cardId;

  /// 0.0–1.0: quanto o parser confia na classificação.
  final double confidence;
}

// ---------------------------------------------------------------------------
// Padrões — mantidos separados por evento para facilitar leitura e testes.
// ---------------------------------------------------------------------------

final _cardRefundRe = RegExp(
  r'\b(estorno|estornad[oa]|credito no cartao|reembolso)\b',
);

final _cardPurchaseRe = RegExp(
  r'\bcompra\b.*\bcartao\b|\bcartao\b.*\bcompra\b|'
  r'\bcompra (?:aprovada|realizada|efetuada)\b|'
  r'\bcartao (?:de credito )?final \d{4}\b',
);

final _accountCreditRe = RegExp(
  r'\bpix recebido\b|\bvoce recebeu\b|\brecebeu (?:um |uma )?(?:pix|transferencia|ted|doc)\b|'
  r'\bdeposito\b|\btransferencia recebida\b|\bted recebid[ao]\b|\bdoc recebid[ao]\b|'
  r'\bsalario\b|\bcredito em conta\b|\bcaiu na (?:sua )?conta\b',
);

final _accountDebitRe = RegExp(
  r'\bpix enviado\b|\bvoce (?:pagou|enviou|transferiu)\b|'
  r'\bcompra no debito\b|\bdebito aprovad[oa]\b|\bdebito de\b|'
  r'\bpagamento (?:realizado|efetuado|aprovado|de conta)\b|'
  r'\btransferencia (?:enviada|realizada|efetuada)\b|\bted enviad[ao]\b|'
  r'\bsaque\b|\bboleto pago\b|\bdebitad[oa]\b',
);

/// Valor em BRL: "R$ 1.234,56", "R$123,45", "12,90", "12.90".
final _brlAmountRe = RegExp(
  r'(?:r\$\s*)?(\d{1,3}(?:\.\d{3})+,\d{2}|\d+,\d{1,2}|\d+\.\d{1,2})',
  caseSensitive: false,
);

/// Valor com prefixo R$ explícito (prioritário — evita capturar "final 1234").
final _brlAmountWithSymbolRe = RegExp(
  r'r\$\s*(\d{1,3}(?:\.\d{3})+(?:,\d{2})?|\d+(?:[.,]\d{1,2})?)',
  caseSensitive: false,
);

/// Estabelecimento/contraparte: "em MERCADO X", "para NETFLIX", "de JOAO".
final _merchantRe = RegExp(
  r'\b(?:em|no estabelecimento|para|de)\s+'
  r'([A-ZÀ-Ü0-9][A-ZÀ-Üa-zà-ü0-9.*&\- ]{1,40}?)'
  r'(?=\s*(?:[,.;]|no valor|valor|r\$|R\$|\d|$))',
);

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éèê]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óòôõ]'), 'o')
    .replaceAll(RegExp('[úù]'), 'u')
    .replaceAll('ç', 'c');

double? _extractAmount(String text) {
  final withSymbol = _brlAmountWithSymbolRe.firstMatch(text);
  if (withSymbol != null) return parseMoney(withSymbol.group(1)!);
  final match = _brlAmountRe.firstMatch(text);
  if (match != null) return parseMoney(match.group(1)!);
  return null;
}

String? _extractMerchant(String text) {
  // Remove o trecho do valor para o nome não engolir "R$ 45,90".
  final cleaned = text
      .replaceAll(_brlAmountWithSymbolRe, ' ')
      .replaceAll(RegExp(r'no valor de\s*', caseSensitive: false), ' ');
  final match = _merchantRe.firstMatch(cleaned);
  final raw = match?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  // Descarta capturas que são só palavras genéricas de frase bancária.
  const noise = {'conta', 'cartao', 'credito', 'debito', 'hoje', 'sua conta'};
  if (noise.contains(_fold(raw))) return null;
  return raw;
}

String? _matchOption(String foldedText, List<VoiceOption> options) {
  for (final o in options) {
    final name = _fold(o.name).trim();
    if (name.length >= 3 && foldedText.contains(name)) return o.id;
  }
  return null;
}

BankEventType? _classify(String folded) {
  // Ordem importa: estorno costuma citar "cartão", então testa antes de
  // compra; compra no cartão cita "compra", então testa antes de débito.
  final mentionsCard = folded.contains('cartao');
  if (mentionsCard && _cardRefundRe.hasMatch(folded)) {
    return BankEventType.cardRefund;
  }
  if (_cardPurchaseRe.hasMatch(folded)) return BankEventType.cardPurchase;
  if (_accountCreditRe.hasMatch(folded)) return BankEventType.accountCredit;
  if (_accountDebitRe.hasMatch(folded)) return BankEventType.accountDebit;
  return null;
}

/// Heurística local (offline) que identifica um evento financeiro no texto de
/// uma notificação bancária. Retorna null quando o texto não parece ser uma
/// movimentação (ex.: propaganda, aviso de fatura, dica de segurança).
///
/// [accounts]/[cards] são as contas e cartões do usuário, usados para sugerir
/// a origem quando o nome/banco aparece no texto ou no nome do app.
BankNotificationParseResult? parseBankNotification({
  required String title,
  required String text,
  String appName = '',
  List<VoiceOption> accounts = const [],
  List<VoiceOption> cards = const [],
}) {
  final full = '$title. $text'.trim();
  final folded = _fold(full);

  final eventType = _classify(folded);
  if (eventType == null) return null;

  final amount = _extractAmount(full);
  // Sem valor não há sugestão útil — evita ruído de avisos genéricos.
  if (amount == null || amount <= 0) return null;

  final isCard =
      eventType == BankEventType.cardPurchase ||
      eventType == BankEventType.cardRefund;
  final transactionType =
      (eventType == BankEventType.accountCredit ||
          eventType == BankEventType.cardRefund)
      ? 'income'
      : 'expense';

  final merchant = _extractMerchant(full);
  final description = merchant ?? _defaultDescription(eventType, appName);

  // Origem: casa nome do cartão/conta com o texto e com o nome do app.
  final searchable = _fold('$full $appName');
  final cardId = isCard ? _matchOption(searchable, cards) : null;
  final accountId = isCard ? null : _matchOption(searchable, accounts);

  var confidence = 0.5;
  if (merchant != null) confidence += 0.2;
  if (cardId != null || accountId != null) confidence += 0.2;
  if (_brlAmountWithSymbolRe.hasMatch(full)) confidence += 0.1;

  return BankNotificationParseResult(
    eventType: eventType,
    transactionType: transactionType,
    amount: amount,
    description: description,
    accountId: accountId,
    cardId: cardId,
    confidence: confidence.clamp(0.0, 1.0),
  );
}

String _defaultDescription(BankEventType eventType, String appName) {
  final suffix = appName.isEmpty ? '' : ' — $appName';
  switch (eventType) {
    case BankEventType.accountDebit:
      return 'Débito em conta$suffix';
    case BankEventType.accountCredit:
      return 'Crédito em conta$suffix';
    case BankEventType.cardPurchase:
      return 'Compra no cartão$suffix';
    case BankEventType.cardRefund:
      return 'Estorno no cartão$suffix';
  }
}
