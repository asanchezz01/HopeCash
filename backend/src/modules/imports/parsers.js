import zlib from 'node:zlib';

/**
 * Parsers de importação (CSV, OFX e PDF com texto) sem dependências externas.
 * Retornam itens normalizados:
 *   { date: 'YYYY-MM-DD', description, amount, kind, fitid?, raw, confidence }
 * kind: debit | credit | card_purchase | card_credit
 * Convenção de sinal do amount: despesa/compra negativa, receita/crédito positiva.
 */

const BR_DATE = /^(\d{2})[/-](\d{2})[/-](\d{4})$/;
const BR_DATE_SHORT = /^(\d{2})[/-](\d{2})$/;
const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})/;

export const normalizeDate = (value, { referenceYear = null } = {}) => {
  if (!value) return null;
  const v = String(value).trim();
  const br = v.match(BR_DATE);
  if (br) return `${br[3]}-${br[2]}-${br[1]}`;
  const iso = v.match(ISO_DATE);
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;
  // Formato OFX: YYYYMMDD[HHMMSS]
  const ofx = v.match(/^(\d{4})(\d{2})(\d{2})/);
  if (ofx) return `${ofx[1]}-${ofx[2]}-${ofx[3]}`;
  // Fatura em PDF costuma trazer só dia/mês; o ano vem do mês de referência.
  const short = v.match(BR_DATE_SHORT);
  if (short && referenceYear) return `${referenceYear}-${short[2]}-${short[1]}`;
  return null;
};

/**
 * Valores brasileiros: "R$ 1.234,56", "1.234,56", "1234.56".
 * Sinal por "-", "+", parênteses contábeis ou indicador D/C (Débito/Crédito).
 */
export const normalizeAmount = (value) => {
  if (value == null) return null;
  let v = String(value).trim();
  if (!v) return null;

  let sign = 1;
  if (/^\(.*\)$/.test(v)) { sign = -1; v = v.slice(1, -1).trim(); }

  // Indicador D/C colado ou separado: "152,30 D", "152,30D", "C 300,00".
  const suffix = v.match(/[\s\d](d|c|d[eé]bito|cr[eé]dito)$/i);
  if (suffix) {
    if (suffix[1].toLowerCase().startsWith('d')) sign = -1;
    v = v.slice(0, v.length - suffix[1].length).trim();
  } else {
    const prefix = v.match(/^(d|c|d[eé]bito|cr[eé]dito)\s+/i);
    if (prefix) {
      if (prefix[1].toLowerCase().startsWith('d')) sign = -1;
      v = v.slice(prefix[0].length);
    }
  }

  v = v.replace(/[R$\s]/gi, '');
  if (v.startsWith('-')) { sign = -sign; v = v.slice(1); }
  else if (v.startsWith('+')) v = v.slice(1);
  if (!v) return null;

  // Formato brasileiro 1.234,56 → 1234.56
  if (/,\d{1,2}$/.test(v)) v = v.replace(/\./g, '').replace(',', '.');
  else if (/^\d{1,3}(\.\d{3})+$/.test(v)) v = v.replace(/\./g, ''); // 1.234 sem centavos
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  return sign * (Math.round(Math.abs(n) * 100) / 100);
};

/**
 * Pagamento da fatura anterior lançado dentro da própria fatura (o C6 exporta
 * "Inclusao de Pagamento" com valor negativo). Não é compra nem estorno: entra
 * como item, distorce o total conciliado e não tem contrapartida no cartão.
 */
const INVOICE_PAYMENT = /\b(inclusao de pagamento|pagamento (recebido|efetuado|realizado|em duplicidade)|pagto (recebido|efetuado))\b/;

/** Linhas de resumo/ruído que não são lançamentos (saldos, totais, limites). */
export const isNoiseDescription = (description, { importKind = null } = {}) => {
  const d = fold(String(description ?? ''));
  if (importKind === 'credit_card_invoice' && INVOICE_PAYMENT.test(d)) return true;
  return /\b(saldo (anterior|atual|final|do dia|em conta|disponivel)|saldo$|^saldo|pagamento minimo|pagamento (da )?fatura|total (da |desta |a pagar|fatura)|valor total|limite (disponivel|total|de credito)|subtotal|resumo da fatura|melhor dia de compra)\b/.test(d);
};

/** Remove números de cartão mascarados e excesso de espaços da descrição. */
export const cleanDescription = (description) => {
  return String(description ?? '')
    .replace(/[*Xx•●]{4,}[\s.]*\d{0,4}/g, ' ')
    .replace(/\d{4,6}[\s.]*[*Xx•●]{4,}/g, ' ')
    .replace(/\s{2,}/g, ' ')
    .trim();
};

/**
 * Detecta marcador de parcelamento na descrição de uma compra de fatura:
 * "LOJA 2/5", "LOJA (2/5)", "PARC 03/10", "PARCELA 2 de 5". Datas no fim da
 * descrição raramente colidem porque exigem número ≤ total e total ≥ 2.
 * Retorna também o trecho casado para permitir reescrever o rótulo das
 * parcelas futuras.
 */
export function detectInstallment(description) {
  const text = String(description ?? '');
  const explicit = /\bparc(?:ela)?\.?\s*(\d{1,2})(?:\s*\/\s*|\s+de\s+)(\d{1,2})\b/i.exec(text);
  const trailing = /(?:^|[\s\-(])(\d{1,2})\s*\/\s*(\d{1,2})\)?\s*$/.exec(text);
  const match = explicit ?? trailing;
  if (!match) return null;
  const number = Number(match[1]);
  const total = Number(match[2]);
  if (number < 1 || total < 2 || number > total || total > 48) return null;
  return { number, total, marker: match[0] };
}

const fold = (s) => s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');

/** Metadados financeiros não transacionais encontrados no documento. */
export function extractInvoiceMetadata(text, opts = {}) {
  if (opts.importKind !== 'credit_card_invoice') return {};
  const metadata = {};
  const normalized = String(text ?? '').replace(/\r/g, '\n');
  const total = normalized.match(/(?:total\s+(?:da|desta)\s+fatura|valor\s+total|total\s+a\s+pagar)\D{0,30}((?:R\$\s*)?-?[\d.]+,\d{2}|-?\d+\.\d{2})/i);
  if (total) metadata.official_total = Math.abs(normalizeAmount(total[1]));
  const due = normalized.match(/(?:vencimento|vence\s+em)\D{0,20}(\d{2}[/-]\d{2}[/-]\d{4}|\d{4}-\d{2}-\d{2})/i);
  if (due) metadata.due_date = normalizeDate(due[1], opts);
  const reference = normalized.match(/(?:refer[eê]ncia|fatura\s+de)\D{0,15}(\d{2}[/-]\d{4})/i);
  if (reference) {
    const [month, year] = reference[1].split(/[/-]/);
    metadata.reference_month = `${year}-${month}-01`;
  }
  const card = normalized.match(/(?:cart[aã]o|final)\D{0,20}(\d{4})\b/i);
  if (card) metadata.card_last_four = card[1];
  for (const [key, label] of Object.entries({
    purchases: 'compras?', fees: 'tarifas?', interest: 'juros?', taxes: 'impostos?',
    credits: 'cr[eé]ditos?', refunds: 'estornos?', payments: 'pagamentos?',
  })) {
    const found = normalized.match(new RegExp(`(?:^|\\n)\\s*${label}\\D{0,20}((?:R\\$\\s*)?-?[\\d.]+,\\d{2}|-?\\d+\\.\\d{2})`, 'i'));
    if (found) metadata[key] = Math.abs(normalizeAmount(found[1]));
  }
  return metadata;
}

const withMetadata = (items, metadata) => {
  Object.defineProperty(items, 'metadata', { value: metadata, enumerable: false });
  return items;
};

/**
 * Direção financeira da linha conforme o modo de importação.
 * - Extrato: positivo = crédito em conta, negativo = débito.
 * - Fatura CSV/PDF: positivo = compra (convenção das faturas), negativo = estorno.
 * - Fatura OFX: convenção invertida (compra vem negativa no OFX de cartão).
 */
export const detectKind = (amount, { importKind = 'bank_statement', source = 'csv' } = {}) => {
  if (importKind === 'credit_card_invoice') {
    const purchaseWhenPositive = source !== 'ofx';
    const isPurchase = purchaseWhenPositive ? amount > 0 : amount < 0;
    return isPurchase ? 'card_purchase' : 'card_credit';
  }
  return amount >= 0 ? 'credit' : 'debit';
};

/** Aplica a convenção de sinal do HopeCash: despesa negativa, receita positiva. */
const signedByKind = (amount, kind) =>
  (kind === 'debit' || kind === 'card_purchase') ? -Math.abs(amount) : Math.abs(amount);

/**
 * `installment` explícito (coluna do arquivo) tem precedência sobre o marcador
 * na descrição; `undefined` significa "não informado, detectar na descrição".
 */
const finalizeItem = ({ date, description, amount, fitid = null, raw, confidence, installment: given }, opts) => {
  const kind = detectKind(amount, opts);
  const clean = cleanDescription(description) || 'Lançamento importado';
  // Somente compras de fatura carregam parcelamento; estornos não projetam
  // parcelas futuras.
  const installment = opts?.importKind === 'credit_card_invoice' && kind === 'card_purchase'
    ? (given === undefined ? detectInstallment(clean) : given)
    : null;
  return {
    date,
    description: clean,
    amount: signedByKind(amount, kind),
    kind,
    fitid,
    raw,
    confidence,
    installment_number: installment?.number ?? null,
    installment_total: installment?.total ?? null,
  };
};

/** Parser CSV com suporte a campos entre aspas e detecção de delimitador (, ou ;). */
export function parseCsv(text) {
  const firstLine = text.split(/\r?\n/, 1)[0] ?? '';
  const delimiter = (firstLine.match(/;/g)?.length ?? 0) > (firstLine.match(/,/g)?.length ?? 0) ? ';' : ',';

  const rows = [];
  let field = '';
  let row = [];
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (ch === '"') inQuotes = false;
      else field += ch;
    } else if (ch === '"') inQuotes = true;
    else if (ch === delimiter) { row.push(field); field = ''; }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (row.some((c) => c.trim() !== '')) rows.push(row);
      row = [];
    } else field += ch;
  }
  if (field !== '' || row.length) { row.push(field); if (row.some((c) => c.trim() !== '')) rows.push(row); }
  return rows;
}

const AMOUNT_NAMES = ['valor', 'amount', 'value', 'quantia', 'montante'];
/** Coluna de moeda estrangeira ou de cotação: não é o valor cobrado na fatura. */
const FOREIGN_AMOUNT = /us\$|u\$|\busd\b|\beur\b|€|dolar|dollar|moeda|cambio|cotacao/;
/** Marcadores de moeda nacional: "Valor (em R$)", "Valor BRL", "Valor em reais". */
const LOCAL_AMOUNT = /r\$|\bbrl\b|reais/;

/** Coluna de valor útil tem ao menos um lançamento diferente de zero. */
const hasUsableAmounts = (rows, index, start) => rows.slice(start, start + 50)
  .some((row) => {
    const n = normalizeAmount(row[index]);
    return n != null && n !== 0;
  });

/**
 * Escolhe a coluna de valor quando o arquivo traz mais de uma — a fatura do C6
 * tem "Valor (em US$)", "Cotação (em R$)" e "Valor (em R$)", e pegar a primeira
 * zera todos os lançamentos nacionais. Vence a coluna com valores de fato,
 * preferindo moeda nacional e descartando conversão/cotação.
 */
const findAmountCol = (header, rows, start) => {
  const candidates = header
    .map((h, index) => ({ h, index }))
    .filter(({ h }) => AMOUNT_NAMES.some((n) => h.includes(n)));
  if (candidates.length <= 1) return candidates[0]?.index ?? -1;
  return candidates
    .map(({ h, index }) => ({
      index,
      score: (hasUsableAmounts(rows, index, start) ? 8 : 0)
        + (LOCAL_AMOUNT.test(h) ? 2 : 0) - (FOREIGN_AMOUNT.test(h) ? 3 : 0),
    }))
    .sort((a, b) => b.score - a.score || a.index - b.index)[0].index;
};

/**
 * Converte CSV em itens usando um mapeamento de colunas
 * { date: 0, description: 1, amount: 2, installment: 5, has_header: true }
 * — índices de coluna. Sem mapeamento, tenta detectar pelas primeiras linhas.
 * opts: { importKind, referenceYear }
 */
export function csvToItems(text, mapping = null, opts = {}) {
  const rows = parseCsv(text);
  if (!rows.length) return withMetadata([], extractInvoiceMetadata(text, opts));

  let map = mapping;
  let start = 0;
  if (!map) {
    // Heurística: procura no cabeçalho colunas conhecidas.
    const header = rows[0].map((h) => fold(h).trim());
    const findCol = (...names) => header.findIndex((h) => names.some((n) => h.includes(n)));
    const dateCol = findCol('data', 'date', 'dt');
    const descCol = findCol('desc', 'hist', 'memo', 'lancamento', 'title', 'titulo', 'estabelecimento');
    const amountCol = findAmountCol(header, rows, 1);
    // "Parcela" é a coluna de parcelamento; "Valor da Parcela" é valor.
    const installmentCol = header.findIndex((h) => /\bparcela(s|mento)?\b/.test(h)
      && !AMOUNT_NAMES.some((n) => h.includes(n)));
    map = {
      date: dateCol >= 0 ? dateCol : 0,
      description: descCol >= 0 ? descCol : 1,
      amount: amountCol >= 0 ? amountCol : 2,
      installment: installmentCol >= 0 ? installmentCol : null,
      has_header: dateCol >= 0 || descCol >= 0 || amountCol >= 0,
    };
  }
  if (map.has_header) start = 1;

  const items = [];
  for (let i = start; i < rows.length; i++) {
    const cols = rows[i];
    const date = normalizeDate(cols[map.date], opts);
    const amount = normalizeAmount(cols[map.amount]);
    const description = String(cols[map.description] ?? '').trim();
    if (!date || amount == null) continue;
    // Valor zerado não altera a fatura e costuma indicar coluna de outra moeda:
    // ignorar evita itens fantasma na conciliação.
    if (amount === 0) continue;
    if (isNoiseDescription(description, opts)) continue;
    const parcel = map.installment == null ? '' : String(cols[map.installment] ?? '').trim();
    items.push(finalizeItem({
      date, description, amount, raw: cols, confidence: 0.9,
      ...(parcel ? { installment: detectInstallment(parcel) } : {}),
    }, { ...opts, source: 'csv' }));
  }
  return withMetadata(items, extractInvoiceMetadata(text, opts));
}

/** Parser OFX: extrai blocos <STMTTRN> (SGML ou XML) — extrato ou cartão. */
export function ofxToItems(text, opts = {}) {
  const items = [];
  const blocks = text.split(/<STMTTRN>/i).slice(1);
  for (const block of blocks) {
    const tag = (name) => {
      const m = block.match(new RegExp(`<${name}>([^<\r\n]*)`, 'i'));
      return m ? m[1].trim() : null;
    };
    const date = normalizeDate(tag('DTPOSTED'), opts);
    const amount = normalizeAmount(tag('TRNAMT'));
    const description = tag('MEMO') || tag('NAME') || '';
    if (!date || amount == null) continue;
    if (isNoiseDescription(description, opts)) continue;
    items.push(finalizeItem({
      date,
      description,
      amount,
      fitid: tag('FITID'),
      raw: { DTPOSTED: tag('DTPOSTED'), TRNAMT: tag('TRNAMT'), MEMO: tag('MEMO'), NAME: tag('NAME'), FITID: tag('FITID') },
      confidence: 0.95,
    }, { ...opts, source: 'ofx' }));
  }
  const metadata = extractInvoiceMetadata(text, opts);
  if (opts.importKind === 'credit_card_invoice' && metadata.official_total == null) {
    const balance = text.match(/<BALAMT>([^<\r\n]*)/i);
    if (balance) metadata.official_total = Math.abs(normalizeAmount(balance[1]));
  }
  return withMetadata(items, metadata);
}

// ---------------------------------------------------------------------------
// PDF com texto extraível
// ---------------------------------------------------------------------------

const decodePdfString = (token) => {
  if (token.startsWith('<')) {
    const hex = token.slice(1, -1).replace(/\s/g, '');
    let out = '';
    for (let i = 0; i + 1 < hex.length; i += 2) {
      out += String.fromCharCode(parseInt(hex.slice(i, i + 2), 16));
    }
    return out;
  }
  const body = token.slice(1, -1);
  let out = '';
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (ch !== '\\') { out += ch; continue; }
    const next = body[++i];
    if (next === 'n') out += '\n';
    else if (next === 'r') out += '\r';
    else if (next === 't') out += '\t';
    else if (next >= '0' && next <= '7') {
      let oct = next;
      while (oct.length < 3 && body[i + 1] >= '0' && body[i + 1] <= '7') oct += body[++i];
      out += String.fromCharCode(parseInt(oct, 8));
    } else if (next === '\n' || next === '\r') { /* continuação de linha */ }
    else out += next; // \( \) \\ e demais escapes literais
  }
  return out;
};

// Converte um content stream em texto: strings viram texto;
// operadores de posicionamento (Td, TD, T-asterisco, Tm, ET) viram quebra.
const contentStreamToText = (content) => {
  let out = '';
  const re = /\((?:\\.|[^\\()])*\)|<[0-9A-Fa-f\s]+>|\bT[dD*]\b|\bTm\b|\bET\b/g;
  let m;
  while ((m = re.exec(content)) !== null) {
    const token = m[0];
    if (token.startsWith('(') || token.startsWith('<')) out += `${decodePdfString(token)} `;
    else out += '\n';
  }
  return out;
};

/**
 * Extrai o texto de um PDF nato-digital (streams FlateDecode ou sem filtro).
 * Retorna '' para PDFs escaneados/imagem — o chamador decide o erro amigável.
 */
export function extractPdfText(buffer) {
  const src = buffer.toString('latin1');
  const parts = [];
  const streamRe = /<<([^]*?)>>\s*stream\r?\n/g;
  let m;
  while ((m = streamRe.exec(src)) !== null) {
    const dict = m[1];
    if (/\/Subtype\s*\/Image|\/(DCTDecode|CCITTFaxDecode|JPXDecode|JBIG2Decode)/.test(dict)) continue;
    const start = m.index + m[0].length;
    const end = src.indexOf('endstream', start);
    if (end < 0) continue;
    let data = buffer.subarray(start, end);
    while (data.length && (data[data.length - 1] === 0x0a || data[data.length - 1] === 0x0d)) {
      data = data.subarray(0, data.length - 1);
    }
    if (/\/FlateDecode/.test(dict)) {
      try { data = zlib.inflateSync(data); }
      catch { try { data = zlib.inflateRawSync(data); } catch { continue; } }
    } else if (/\/Filter/.test(dict)) {
      continue; // filtro não suportado (LZW etc.)
    }
    const content = data.toString('latin1');
    if (/\bBT\b/.test(content) || /\bTj\b|\bTJ\b/.test(content)) {
      parts.push(contentStreamToText(content));
    }
  }
  return parts.join('\n');
}

/**
 * Interpreta texto tabular (linhas de extrato/fatura em PDF):
 * data no início da linha, valor (com D/C opcional) no fim, descrição no meio.
 * opts: { importKind, referenceYear }
 */
export function textToItems(text, opts = {}) {
  const items = [];
  const lineRe = /^(\d{2}[/-]\d{2}(?:[/-]\d{4})?|\d{4}-\d{2}-\d{2})\s+(.+?)\s+(-?\s*(?:R\$\s*)?\d{1,3}(?:\.\d{3})*,\d{2}(?:\s*[DC])?|-?\d+\.\d{2}(?:\s*[DC])?)\s*$/i;
  for (const rawLine of text.split(/\n/)) {
    const line = rawLine.replace(/\s+/g, ' ').trim();
    if (!line) continue;
    const m = line.match(lineRe);
    if (!m) continue;
    const date = normalizeDate(m[1], opts);
    const amount = normalizeAmount(m[3]);
    const description = m[2].trim();
    if (!date || amount == null) continue;
    if (isNoiseDescription(description, opts)) continue;
    items.push(finalizeItem({
      date, description, amount, raw: { line }, confidence: 0.6,
    }, { ...opts, source: 'pdf' }));
  }
  return withMetadata(items, extractInvoiceMetadata(text, opts));
}

/** PDF → itens. Lança erro com `friendly` quando o PDF não tem texto legível. */
export function pdfToItems(buffer, opts = {}) {
  const text = extractPdfText(buffer);
  const hasReadableText = /[A-Za-zÀ-ú]{3,}/.test(text);
  if (!hasReadableText) {
    const err = new Error('PDF sem texto selecionável');
    err.friendly = 'Não foi possível ler o PDF: ele parece ser escaneado ou conter apenas imagens. '
      + 'Envie um PDF com texto selecionável (gerado pelo banco) ou exporte em CSV/OFX.';
    throw err;
  }
  return textToItems(text, opts);
}
