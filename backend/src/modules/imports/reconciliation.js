const DAY_MS = 86_400_000;

/** Crédito em qualquer fluxo: fatura usa 'card_credit', extrato usa 'credit'. */
export const isCreditKind = (kind) => kind === 'card_credit' || kind === 'credit';

export const toCents = (value) => {
  if (value == null || value === '') return null;
  const normalized = typeof value === 'string'
    ? (value.includes(',') ? value.trim().replace(/\./g, '').replace(',', '.') : value.trim())
    : String(value);
  // Converte a parte decimal por aritmética inteira. Isso evita que valores
  // como 10,005 sejam decididos por arredondamento binário de double.
  const match = normalized.match(/^([+-]?)(\d+)(?:\.(\d+))?$/);
  if (!match) return null;
  const sign = match[1] === '-' ? -1 : 1;
  const whole = BigInt(match[2]);
  const fraction = match[3] ?? '';
  const centsPart = Number(`${fraction}00`.slice(0, 2));
  const roundingDigit = fraction.length > 2 ? Number(fraction[2]) : 0;
  const cents = whole * 100n + BigInt(centsPart + (roundingDigit >= 5 ? 1 : 0));
  return sign * Number(cents);
};

/**
 * Valor que o lançamento representa para a conciliação. Lançamento já pago
 * moveu dinheiro pelo `amount` real — é isso que o extrato registra; previsto
 * ainda vale pelo `amount_planned`. Usar sempre o previsto faz uma baixa cujo
 * valor pago diverge do previsto (baixa parcial, acréscimo, quitação de extra
 * junto com a parcela) nunca casar com a linha do extrato.
 */
export const transactionValue = (transaction) => (transaction.status === 'paid'
  ? (transaction.amount ?? transaction.amount_planned)
  : (transaction.amount_planned ?? transaction.amount));

export const transactionEffectCents = (transaction) => {
  const cents = Math.abs(toCents(transactionValue(transaction)) ?? 0);
  return transaction.type === 'income' ? -cents : cents;
};

export const statementEffectCents = (item) => {
  const cents = Math.abs(item.amount_cents ?? toCents(item.amount) ?? 0);
  return isCreditKind(item.kind) ? -cents : cents;
};

export const normalizeDescription = (value) => String(value ?? '')
  .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase()
  .replace(/\b(?:compra|cartao|credito|debito|lancamento|pagto|visa|mastercard)\b/g, ' ')
  .replace(/(?:\*|x|•){3,}\s*\d{0,4}/gi, ' ')
  .replace(/[^a-z0-9 ]/g, ' ')
  .replace(/\s+/g, ' ').trim();

const dayDistance = (a, b) => Math.abs(
  (Date.parse(`${String(a).slice(0, 10)}T00:00:00Z`) - Date.parse(`${String(b).slice(0, 10)}T00:00:00Z`)) / DAY_MS,
);

const descriptionScore = (a, b) => {
  const x = new Set(normalizeDescription(a).split(' ').filter(Boolean));
  const y = new Set(normalizeDescription(b).split(' ').filter(Boolean));
  if (!x.size || !y.size) return 0;
  let common = 0;
  for (const token of x) if (y.has(token)) common += 1;
  return common / Math.max(x.size, y.size);
};

const compatibleType = (item, tx) =>
  (isCreditKind(item.kind) ? tx.type === 'income' : tx.type === 'expense');

/**
 * A fatura repete a data da compra original em todas as parcelas, enquanto a
 * parcela no HopeCash tem a competência do próprio ciclo — a distância entre as
 * datas cresce a cada mês. Quando parcela e total coincidem, essa identidade
 * substitui a proximidade de datas: o ciclo já foi filtrado pelo vencimento.
 */
const sameInstallment = (item, tx) => {
  const number = Number(item.installment_number);
  const total = Number(item.installment_total);
  return Number.isInteger(number) && Number.isInteger(total) && total > 1
    && Number(tx.installment_number) === number && Number(tx.installment_total) === total;
};

/**
 * Correspondência estável, determinística e um-para-um.
 *
 * `cycleBound`: os lançamentos recebidos já foram filtrados pelo vencimento da
 * fatura, então todos pertencem ao ciclo. A fatura não informa vencimento por
 * lançamento — o C6 traz a data da compra, que pode estar meses antes — e a
 * competência digitada à mão costuma ser o próprio vencimento. Nesse caso a
 * data deixa de filtrar e passa só a ordenar; valor em centavos, tipo e cartão
 * continuam sendo exigidos, e empates viram ambiguidade para o usuário decidir.
 */
export function reconcileItems(statementItems, transactions, { toleranceDays = 3, cycleBound = false } = {}) {
  const claimed = new Set();
  const results = [];
  const sortedTx = [...transactions].sort((a, b) => String(a.id).localeCompare(String(b.id)));

  for (let index = 0; index < statementItems.length; index += 1) {
    const item = statementItems[index];
    const effect = statementEffectCents(item);
    const candidates = sortedTx.filter((tx) => {
      if (claimed.has(tx.id) || !compatibleType(item, tx)) return false;
      if (transactionEffectCents(tx) !== effect) return false;
      if (cycleBound || sameInstallment(item, tx)) return true;
      return dayDistance(item.date ?? item.item_date, tx.competence_date) <= toleranceDays;
    }).map((tx) => {
      const days = dayDistance(item.date ?? item.item_date, tx.competence_date);
      const desc = descriptionScore(item.description, tx.description);
      const fitid = Boolean(item.fitid && tx.external_id && item.fitid === tx.external_id);
      const installment = sameInstallment(item, tx);
      // Piso no termo de data: dentro do ciclo, a distância só desempata e não
      // pode empurrar a pontuação para valores negativos.
      const byDate = (days === 0 ? 100 : Math.max(10, 70 - days * 10)) + Math.round(desc * 20);
      const score = fitid ? 1000 : installment ? Math.max(200 + Math.round(desc * 20), byDate) : byDate;
      return { tx, days, desc, score, fitid, installment };
    }).sort((a, b) => b.score - a.score || String(a.tx.id).localeCompare(String(b.tx.id)));

    if (!candidates.length) {
      results.push({ item, matchType: 'statement_only', confidence: 0, candidates: [] });
      continue;
    }
    const best = candidates[0];
    const tied = candidates.filter((c) => c.score === best.score);
    // Ocorrências realmente repetidas são pareadas por ordem estável quando a
    // quantidade restante de itens cobre todos os candidatos equivalentes.
    const repeatedRemaining = statementItems.slice(index).filter((other) =>
      other.kind === item.kind
      && statementEffectCents(other) === effect
      && String(other.date ?? other.item_date) === String(item.date ?? item.item_date)
      && normalizeDescription(other.description) === normalizeDescription(item.description)).length;
    if (tied.length > 1 && repeatedRemaining < tied.length) {
      results.push({
        item, matchType: 'ambiguous', confidence: Math.min(best.score, 99),
        candidates: candidates.map((c) => c.tx.id),
        reason: `${tied.length} candidatos com mesmo valor, tipo e pontuação`,
      });
      continue;
    }
    claimed.add(best.tx.id);
    const exact = best.days === 0;
    results.push({
      item, transaction: best.tx, matchType: exact ? 'exact_match' : 'probable_match',
      confidence: exact ? Math.min(100, 90 + Math.round(best.desc * 10)) : Math.min(89, best.score),
      candidates: candidates.map((c) => c.tx.id),
      reason: exact
        ? 'Mesmo cartão, ciclo, tipo, valor em centavos e data'
        : best.installment
          ? `Mesma parcela ${item.installment_number}/${item.installment_total}, valor e ciclo`
          : `Mesmo cartão, ciclo, tipo e valor; datas diferem em ${best.days} dia(s)`,
    });
  }

  return {
    statement: results,
    hopecashOnly: sortedTx.filter((tx) => !claimed.has(tx.id)),
  };
}

export function reconciliationSummary(batch, items) {
  const current = Number(batch.current_total_cents ?? 0);
  let projected = current;
  let additions = 0;
  let removals = 0;
  const missing = [];

  for (const item of items) {
    const payload = typeof item.decision_payload === 'string'
      ? JSON.parse(item.decision_payload || '{}') : (item.decision_payload ?? {});
    if (item.item_origin === 'hopecash') {
      const original = Number(item.amount_cents ?? 0);
      if (item.decision === 'remove') { projected -= original; removals += original; }
      else if (item.decision === 'edit') {
        const edited = Number(payload.effect_cents ?? original);
        projected += edited - original;
      } else if (!item.decision) missing.push(item.id);
    } else if (item.decision === 'create') {
      const effect = statementEffectCents(item);
      projected += effect; additions += effect;
      // Quitação de fatura não é despesa nova — o gasto já foi contado em cada
      // compra do cartão —, então é a única criação de débito sem categoria.
      if (!isCreditKind(item.kind) && payload.settlement_type !== 'card'
        && !(payload.category_id ?? item.suggested_category_id)) missing.push(item.id);
    } else if (!item.decision) missing.push(item.id);
  }
  const official = batch.official_total_cents == null ? null : Number(batch.official_total_cents);
  // Fatura sempre exige total oficial; extrato deixa opcional (quando informado,
  // passa a ser exigido — o usuário confere o saldo que tem em mãos).
  const requireOfficial = batch.import_kind === 'credit_card_invoice';
  const totalMatches = requireOfficial
    ? official != null && official === projected
    : official == null || official === projected;
  return {
    official_total_cents: official,
    recognized_total_cents: Number(batch.recognized_total_cents ?? 0),
    current_total_cents: current,
    additions_cents: additions,
    removals_cents: removals,
    projected_total_cents: projected,
    difference_cents: official == null ? null : official - projected,
    missing_decision_item_ids: [...new Set(missing)],
    can_complete: missing.length === 0 && totalMatches,
  };
}
