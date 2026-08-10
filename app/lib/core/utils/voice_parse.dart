import 'money.dart';

/// Opção nomeável (categoria, conta ou cartão) para casamento por nome.
class VoiceOption {
  const VoiceOption({required this.id, required this.name, this.type});

  final String id;
  final String name;

  /// income | expense (apenas para categorias).
  final String? type;
}

/// Lançamento extraído de uma frase falada.
class VoiceParseResult {
  const VoiceParseResult({
    required this.type,
    this.amount,
    required this.description,
    required this.date,
    this.categoryId,
    this.accountId,
    this.cardId,
    this.installments = 1,
    this.paid = true,
    required this.source,
  });

  /// income | expense
  final String type;
  final double? amount;
  final String description;

  /// YYYY-MM-DD
  final String date;
  final String? categoryId;
  final String? accountId;
  final String? cardId;
  final int installments;
  final bool paid;

  /// 'ai' (backend/Ollama) | 'local' (heurística offline)
  final String source;
}

final _incomeWords = RegExp(
  r'\b(recebi|caiu|entrou|ganhei|sal[aá]rio|receita|dep[oó]sito|pix recebido)\b',
);
final _unpaidWords = RegExp(r'\b(vou pagar|ainda n[aã]o paguei|a pagar|previsto)\b');
final _installmentsRe = RegExp(r'\bem\s+(\d{1,2})\s*(vezes|x|parcelas)\b|\b(\d{1,2})\s*x\b');

// ---------------------------------------------------------------------------
// Valor falado: o STT pode entregar dígitos ("45,50") ou por extenso
// ("cem reais e vinte" = R$ 100,20; "mil e quinhentos"; "dois e cinquenta
// centavos"). O scanner abaixo entende os dois formatos.
// ---------------------------------------------------------------------------

/// Palavras-número em pt-BR (texto já "foldado", sem acentos).
/// "mil" é tratado à parte por ser multiplicador.
const Map<String, int> _numberWords = {
  'zero': 0,
  'um': 1, 'uma': 1, 'dois': 2, 'duas': 2, 'tres': 3, 'quatro': 4,
  'cinco': 5, 'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9,
  'dez': 10, 'onze': 11, 'doze': 12, 'treze': 13,
  'catorze': 14, 'quatorze': 14, 'quinze': 15, 'dezesseis': 16,
  'dezessete': 17, 'dezoito': 18, 'dezenove': 19,
  'vinte': 20, 'trinta': 30, 'quarenta': 40, 'cinquenta': 50,
  'sessenta': 60, 'setenta': 70, 'oitenta': 80, 'noventa': 90,
  'cem': 100, 'cento': 100, 'duzentos': 200, 'trezentos': 300,
  'quatrocentos': 400, 'quinhentos': 500, 'seiscentos': 600,
  'setecentos': 700, 'oitocentos': 800, 'novecentos': 900,
};

const _currencyWords = {'real', 'reais', 'conto', 'contos', 'pila', 'pilas'};
const _installmentWords = {'vezes', 'x', 'parcela', 'parcelas'};

final _tokenRe = RegExp(r'[0-9]+(?:[.,][0-9]+)*|[a-z]+');
final _decimalRe = RegExp(r'[.,]');
final _digitsRe = RegExp(r'^[0-9]+$');

class _Token {
  const _Token(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;
}

/// Sequência de tokens numéricos já convertida ("cento e vinte" → 120).
class _NumberRun {
  const _NumberRun({
    required this.value,
    required this.isDecimal,
    required this.endIdx,
    required this.startPos,
    required this.endPos,
  });

  final double value;

  /// true quando veio de um token com separador decimal ("45,50").
  final bool isDecimal;
  final int endIdx;
  final int startPos;
  final int endPos;
}

double? _faceValue(String? t) {
  if (t == null) return null;
  if (t == 'mil') return 1000;
  if (_digitsRe.hasMatch(t)) return double.tryParse(t);
  return _numberWords[t]?.toDouble();
}

/// Lê a partir de [i] a maior sequência numérica válida.
/// Junta componentes por "e" apenas em ordem decrescente ("cento e vinte" ok;
/// "dois e cinquenta" não junta — provavelmente são reais e centavos).
_NumberRun? _readNumberRun(List<_Token> tokens, int i) {
  if (i >= tokens.length) return null;
  final first = tokens[i];
  if (_digitsRe.hasMatch(first.text.replaceAll(_decimalRe, '')) &&
      _decimalRe.hasMatch(first.text)) {
    final v = parseMoney(first.text);
    if (v == null) return null;
    return _NumberRun(
      value: v,
      isDecimal: true,
      endIdx: i + 1,
      startPos: first.start,
      endPos: first.end,
    );
  }

  var total = 0.0;
  var current = 0.0;
  var lastFace = double.infinity;
  var any = false;
  var j = i;
  var endPos = first.end;
  while (j < tokens.length) {
    final txt = tokens[j].text;
    if (txt == 'e') {
      if (!any) break;
      final next = _faceValue(j + 1 < tokens.length ? tokens[j + 1].text : null);
      if (next == null || next >= lastFace) break;
      j++;
      continue;
    }
    if (txt == 'mil') {
      current = (current == 0 ? 1 : current) * 1000;
      total += current;
      current = 0;
      lastFace = 1000;
      any = true;
      endPos = tokens[j].end;
      j++;
      continue;
    }
    if (_decimalRe.hasMatch(txt)) break; // decimal só vale como token inicial
    final face = _faceValue(txt);
    if (face == null) break;
    if (any && face >= lastFace) break;
    current += face;
    lastFace = face;
    any = true;
    endPos = tokens[j].end;
    j++;
  }
  if (!any) return null;
  return _NumberRun(
    value: total + current,
    isDecimal: false,
    endIdx: j,
    startPos: first.start,
    endPos: endPos,
  );
}

class _SpokenAmount {
  const _SpokenAmount({
    required this.amount,
    required this.start,
    required this.end,
    this.installments,
  });

  final double amount;

  /// Trecho do texto ocupado pelo valor (para remoção da descrição).
  final int start;
  final int end;

  /// Parcelas ditas por extenso ("em tres vezes"), se houver.
  final int? installments;
}

/// Encontra o primeiro valor monetário falado — em dígitos ou por extenso —
/// ignorando números de parcelamento ("3 vezes", "3x").
_SpokenAmount? _findSpokenAmount(String folded) {
  final tokens = [
    for (final m in _tokenRe.allMatches(folded))
      _Token(m.group(0)!, m.start, m.end),
  ];

  int? installments;
  int? readInstallments(_NumberRun run, int afterIdx) {
    if (afterIdx < tokens.length &&
        _installmentWords.contains(tokens[afterIdx].text) &&
        !run.isDecimal &&
        run.value >= 2 &&
        run.value <= 24) {
      return run.value.toInt();
    }
    return null;
  }

  var i = 0;
  while (i < tokens.length) {
    final run = _readNumberRun(tokens, i);
    if (run == null) {
      i++;
      continue;
    }
    var j = run.endIdx;

    // "3 vezes"/"3x": parcelamento, não valor.
    final asInstallments = readInstallments(run, j);
    if (asInstallments != null) {
      installments ??= asInstallments;
      i = j + 1;
      continue;
    }

    var amount = run.value;
    var endPos = run.endPos;

    // "cinquenta centavos"
    if (!run.isDecimal &&
        run.value < 100 &&
        j < tokens.length &&
        tokens[j].text.startsWith('centavo')) {
      amount = run.value / 100;
      endPos = tokens[j].end;
      j++;
    } else {
      var hasCurrency = false;
      if (j < tokens.length && _currencyWords.contains(tokens[j].text)) {
        hasCurrency = true;
        endPos = tokens[j].end;
        j++;
      }
      // Centavos após o valor: "cem reais e vinte", "dois e cinquenta
      // centavos" (sem "reais" o sufixo "centavos" é obrigatório).
      if (!run.isDecimal && j < tokens.length && tokens[j].text == 'e') {
        final cents = _readNumberRun(tokens, j + 1);
        if (cents != null &&
            !cents.isDecimal &&
            cents.value > 0 &&
            cents.value < 100 &&
            readInstallments(cents, cents.endIdx) == null) {
          final centsWord = cents.endIdx < tokens.length &&
              tokens[cents.endIdx].text.startsWith('centavo');
          if (hasCurrency || centsWord) {
            amount += cents.value / 100;
            endPos = centsWord ? tokens[cents.endIdx].end : cents.endPos;
            j = centsWord ? cents.endIdx + 1 : cents.endIdx;
          }
        }
      }
    }

    // Segue procurando parcelas por extenso depois do valor.
    var k = j;
    while (installments == null && k < tokens.length) {
      final r2 = _readNumberRun(tokens, k);
      if (r2 == null) {
        k++;
        continue;
      }
      installments = readInstallments(r2, r2.endIdx);
      k = r2.endIdx + 1;
    }

    return _SpokenAmount(
      amount: amount,
      start: run.startPos,
      end: endPos,
      installments: installments,
    );
  }
  return null;
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éèê]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óòôõ]'), 'o')
    .replaceAll(RegExp('[úù]'), 'u')
    .replaceAll('ç', 'c');

String? _matchOption(String foldedTranscript, List<VoiceOption> options) {
  for (final o in options) {
    final name = _fold(o.name);
    if (name.isNotEmpty && foldedTranscript.contains(name)) return o.id;
  }
  return null;
}

String _relativeDate(String folded, DateTime now) {
  var d = now;
  if (folded.contains('anteontem')) {
    d = now.subtract(const Duration(days: 2));
  } else if (folded.contains('ontem')) {
    d = now.subtract(const Duration(days: 1));
  }
  return d.toIso8601String().substring(0, 10);
}

/// Heurística offline: extrai o que der da frase, sem depender de rede.
/// Usada como fallback quando o backend/LLM está indisponível.
VoiceParseResult parseVoiceLocally(
  String transcript, {
  List<VoiceOption> categories = const [],
  List<VoiceOption> accounts = const [],
  List<VoiceOption> cards = const [],
  DateTime? now,
}) {
  final folded = _fold(transcript);
  final type = _incomeWords.hasMatch(folded) ? 'income' : 'expense';

  // Dígitos ("45,50") ou por extenso ("cem reais e vinte" = 100,20).
  final spoken = _findSpokenAmount(folded);
  final amount = spoken?.amount;

  var installments = 1;
  final inst = _installmentsRe.firstMatch(folded);
  if (inst != null) {
    installments =
        (int.tryParse(inst.group(1) ?? inst.group(3) ?? '') ?? 1).clamp(1, 24).toInt();
  } else if (spoken?.installments != null) {
    installments = spoken!.installments!.clamp(1, 24).toInt();
  }

  final cardId = type == 'expense' ? _matchOption(folded, cards) : null;
  final accountId = cardId == null ? _matchOption(folded, accounts) : null;
  final categoryId = _matchOption(
    folded,
    categories.where((c) => c.type == null || c.type == type).toList(),
  );

  // Descrição: frase sem o trecho do valor, verbos de lançamento e meio de
  // pagamento falado ("no débito", "no pix"...). O _fold preserva o tamanho
  // do texto, então os offsets do valor valem para o transcript original.
  var description = transcript;
  if (spoken != null) {
    description = description.replaceRange(spoken.start, spoken.end, ' ');
  }
  description = description
      .replaceFirst(
        RegExp(
          r'^\s*(gastei|paguei|comprei|recebi|ganhei|lancei|anota[r]?|registra[r]?)\s+',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'\b(no|na|em)\s+(d[eé]bito|cr[eé]dito|dinheiro|pix)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceFirst(
        RegExp(r'^\s*(de|do|da|no|na|em|com)\s+', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  if (description.isEmpty) description = transcript.trim();

  return VoiceParseResult(
    type: type,
    amount: amount,
    description: description,
    date: _relativeDate(folded, now ?? DateTime.now()),
    categoryId: categoryId,
    accountId: accountId,
    cardId: cardId,
    installments: cardId != null ? installments : 1,
    paid: !_unpaidWords.hasMatch(folded),
    source: 'local',
  );
}
