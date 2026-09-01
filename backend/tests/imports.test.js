import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';
import { db } from '../src/db/knex.js';
import { now } from '../src/utils/time.js';
import {
  normalizeAmount, csvToItems, ofxToItems, textToItems, pdfToItems, detectInstallment,
} from '../src/modules/imports/parsers.js';
import { cardDueDate } from '../src/modules/imports/imports.routes.js';
import {
  reconcileItems, reconciliationSummary, toCents, transactionEffectCents,
} from '../src/modules/imports/reconciliation.js';

let api;
let token;
let userId;
let accountId;
let cardId;
let categoryId;

const CSV = `Data;Descrição;Valor
01/07/2026;SUPERMERCADO BOM PRECO;-152,30
02/07/2026;PIX RECEBIDO JOAO;300,00
03/07/2026;POSTO SHELL;-210,55
`;

const OFX = `OFXHEADER:100
<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260701<TRNAMT>-152.30<FITID>ABC1<MEMO>SUPERMERCADO BOM PRECO</STMTTRN>
<STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20260702<TRNAMT>300.00<FITID>ABC2<MEMO>PIX RECEBIDO JOAO</STMTTRN>
</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>`;

// Fatura de cartão: compras positivas, estorno negativo, linhas de resumo.
const INVOICE_CSV = `date,title,amount
2026-06-12,IFOOD RESTAURANTE,89.90
2026-06-15,SUPERMERCADO BOM PRECO,152.30
2026-06-20,ESTORNO LOJA XYZ,-35.00
2026-06-30,Total da fatura,207.20
2026-06-30,Pagamento mínimo,50.00
`;

// Fatura do C6: duas colunas "Valor" (US$ e R$) mais a cotação, parcela em
// coluna própria ("4/12", "Única"), cartões adicionais e o pagamento da fatura
// anterior na mesma lista. Decimais com ponto, delimitador ponto e vírgula.
const C6_INVOICE_CSV = `Data de Compra;Nome no Cartão;Final do Cartão;Categoria;Descrição;Parcela;Valor (em US$);Cotação (em R$);Valor (em R$)
30/03/2026;ANDERSON SANCHEZ;2685;Assistência médica e odontológica;G GUIDOLIN LTDA;4/12;0;0;93.07
01/07/2026;ANDERSON SANCHEZ;2685;Restaurante / Lanchonete / Bar;DOG KING;Única;0;0;23.50
08/07/2026;ANDERSON SANCHEZ;2685;Elétrico;ANTHROPIC* CLAUDE SUB  SA;Única;21.32;5.42;115.45
30/06/2026;ANDERSON SANCHEZ;4775;-;"Inclusao de Pagamento    ";Única;0;0;-6631.77
04/07/2026;ALESSANDRA SANCHEZ;9432;-;SHEIN       *SHEINCOM;Única;0;0;-34.70
`;

/** Gera um PDF mínimo com uma página de texto (stream FlateDecode). */
function makeTextPdf(lines) {
  const content = [
    'BT /F1 10 Tf 40 800 Td',
    ...lines.map((l) => `(${l.replace(/([()\\])/g, '\\$1')}) Tj 0 -14 Td`),
    'ET',
  ].join('\n');
  const stream = zlib.deflateSync(Buffer.from(content, 'latin1'));
  const objects = [
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj',
    '3 0 obj << /Type /Page /Parent 2 0 R /Contents 4 0 R >> endobj',
  ];
  const head = Buffer.from('%PDF-1.4\n', 'latin1');
  const body = Buffer.concat([
    Buffer.from(`${objects.join('\n')}\n4 0 obj << /Length ${stream.length} /Filter /FlateDecode >> stream\n`, 'latin1'),
    stream,
    Buffer.from('\nendstream endobj\ntrailer << /Root 1 0 R >>\n%%EOF', 'latin1'),
  ]);
  return Buffer.concat([head, body]);
}

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;
  userId = user.user.id;
  const acc = await api.post('/api/v1/accounts').set(auth(token))
    .send({ name: 'Conta Importação', type: 'checking' });
  accountId = acc.body.data.id;
  const card = await api.post('/api/v1/cards').set(auth(token))
    .send({ name: 'Cartão Importação', limit_amount: 5000, closing_day: 25, due_day: 5 });
  cardId = card.body.data.id;
  const cat = await api.post('/api/v1/categories').set(auth(token))
    .send({ name: 'Mercado Teste', type: 'expense' });
  categoryId = cat.body.data.id;
  await api.post('/api/v1/rules/categorization').set(auth(token)).send({
    name: 'Supermercados', match_field: 'description', operator: 'contains',
    match_value: 'supermercado', category_id: categoryId, priority: 1,
  });
});

describe('Parsers — normalização', () => {
  it('entende formatos brasileiros e indicadores D/C', () => {
    expect(normalizeAmount('R$ 1.234,56')).toBe(1234.56);
    expect(normalizeAmount('1.234,56')).toBe(1234.56);
    expect(normalizeAmount('1234.56')).toBe(1234.56);
    expect(normalizeAmount('-152,30')).toBe(-152.3);
    expect(normalizeAmount('152,30 D')).toBe(-152.3);
    expect(normalizeAmount('152,30D')).toBe(-152.3);
    expect(normalizeAmount('300,00 C')).toBe(300);
    expect(normalizeAmount('152,30 Débito')).toBe(-152.3);
    expect(normalizeAmount('(89,90)')).toBe(-89.9);
    expect(normalizeAmount('+300,00')).toBe(300);
    expect(normalizeAmount('abc')).toBeNull();
  });

  it('CSV de extrato: kind debit/credit e sinal coerente', () => {
    const items = csvToItems(CSV);
    expect(items).toHaveLength(3);
    expect(items[0].kind).toBe('debit');
    expect(items[0].amount).toBe(-152.3);
    expect(items[1].kind).toBe('credit');
    expect(items[1].amount).toBe(300);
    expect(items[0].confidence).toBeGreaterThan(0);
  });

  it('OFX de extrato: fitid preservado e kinds corretos', () => {
    const items = ofxToItems(OFX);
    expect(items).toHaveLength(2);
    expect(items[0].fitid).toBe('ABC1');
    expect(items[0].kind).toBe('debit');
    expect(items[1].kind).toBe('credit');
  });

  it('CSV de fatura: compra positiva vira card_purchase, estorno vira card_credit, resumo é descartado', () => {
    const items = csvToItems(INVOICE_CSV, null, { importKind: 'credit_card_invoice' });
    expect(items).toHaveLength(3); // total e pagamento mínimo fora
    expect(items[0].kind).toBe('card_purchase');
    expect(items[0].amount).toBe(-89.9); // convenção: compra negativa
    expect(items[2].kind).toBe('card_credit');
    expect(items[2].amount).toBe(35);
    expect(items.some((i) => /total da fatura|pagamento m/i.test(i.description))).toBe(false);
  });

  it('OFX de fatura: convenção invertida (compra negativa no arquivo)', () => {
    const items = ofxToItems(OFX, { importKind: 'credit_card_invoice' });
    expect(items[0].kind).toBe('card_purchase'); // -152.30
    expect(items[1].kind).toBe('card_credit'); // +300.00
  });

  it('texto tabular (PDF): datas dd/mm com ano de referência, D/C e ruído', () => {
    const text = [
      'EXTRATO DE CONTA CORRENTE',
      'Saldo anterior 1.000,00',
      '01/07 PAGAMENTO BOLETO ENERGIA 189,90 D',
      '02/07/2026 PIX RECEBIDO MARIA 250,00 C',
      'Limite disponível 5.000,00',
    ].join('\n');
    const items = textToItems(text, { referenceYear: 2026 });
    expect(items).toHaveLength(2);
    expect(items[0]).toMatchObject({ date: '2026-07-01', kind: 'debit', amount: -189.9 });
    expect(items[1]).toMatchObject({ date: '2026-07-02', kind: 'credit', amount: 250 });
  });

  it('PDF com texto extraível é lido; PDF sem texto retorna erro amigável', () => {
    const pdf = makeTextPdf([
      '10/06/2026 LIVRARIA CULTURA 120,00',
      '11/06/2026 ESTORNO LOJA ABC -35,00',
    ]);
    const items = pdfToItems(pdf, { importKind: 'credit_card_invoice' });
    expect(items).toHaveLength(2);
    expect(items[0].kind).toBe('card_purchase');
    expect(items[1].kind).toBe('card_credit');

    const scanned = Buffer.from('%PDF-1.4\nsem streams de texto\n%%EOF', 'latin1');
    expect(() => pdfToItems(scanned)).toThrowError(/selecionável/i);
  });

  it('fatura do C6: valor em reais, parcela da coluna própria e pagamento da fatura fora', () => {
    const items = csvToItems(C6_INVOICE_CSV, null, { importKind: 'credit_card_invoice' });
    expect(items).toHaveLength(4); // o pagamento da fatura anterior não é lançamento

    const dolar = items.find((i) => i.description.includes('ANTHROPIC'));
    expect(dolar.amount).toBe(-115.45); // valor em R$, não os US$ 21,32 nem a cotação
    expect(items.every((i) => i.amount !== 0)).toBe(true);

    const parcelada = items.find((i) => i.description.includes('GUIDOLIN'));
    expect(parcelada).toMatchObject({
      date: '2026-03-30', amount: -93.07, kind: 'card_purchase',
      installment_number: 4, installment_total: 12,
    });
    // "Única" na coluna de parcela é compra à vista, não parcelamento.
    expect(items.find((i) => i.description === 'DOG KING').installment_total).toBeNull();

    const estorno = items.find((i) => i.description.includes('SHEIN'));
    expect(estorno).toMatchObject({ kind: 'card_credit', amount: 34.7 });
    expect(items.some((i) => /pagamento/i.test(i.description))).toBe(false);
  });

  it('remove números de cartão mascarados da descrição', () => {
    const items = csvToItems('Data;Descrição;Valor\n01/07/2026;COMPRA **** 1234 LOJA X;-10,00\n');
    expect(items[0].description).not.toContain('****');
    expect(items[0].description).toContain('LOJA X');
  });
});

describe('cardDueDate', () => {
  it('compra antes do fechamento vence no mês seguinte (dueDay < closingDay)', () => {
    // fechamento 25, vencimento 5: compra 12/06 fecha 25/06 e vence 05/07
    expect(cardDueDate('2026-06-12', 25, 5)).toBe('2026-07-05');
  });
  it('compra após o fechamento empurra uma fatura', () => {
    expect(cardDueDate('2026-06-28', 25, 5)).toBe('2026-08-05');
  });
});

describe('Conciliação determinística', () => {
  it('converte valores em centavos sem depender da representação binária', () => {
    expect(toCents('10,005')).toBe(1001);
    expect(toCents('10,004')).toBe(1000);
    expect(toCents('-0,01')).toBe(-1);
  });

  const tx = (id, date, amount = 10, type = 'expense', description = 'LOJA TESTE') => ({
    id, card_id: cardId, due_date: '2026-07-05', competence_date: date,
    amount_planned: amount, type, description, version: 1,
  });
  const item = (date, amount = -10, kind = 'card_purchase', description = 'Loja teste') => ({
    date, amount, amount_cents: toCents(amount), kind, description,
  });

  it('distingue exata, provável em até 3 dias e somente fatura fora da tolerância', () => {
    expect(reconcileItems([item('2026-06-10')], [tx('a', '2026-06-10')]).statement[0].matchType).toBe('exact_match');
    for (const days of [1, 2, 3]) {
      const day = String(10 + days).padStart(2, '0');
      expect(reconcileItems([item('2026-06-10')], [tx(`p${days}`, `2026-06-${day}`)]).statement[0].matchType).toBe('probable_match');
    }
    expect(reconcileItems([item('2026-06-10')], [tx('far', '2026-06-14')]).statement[0].matchType).toBe('statement_only');
  });

  it('valor/data prevalecem sobre descrição e dois candidatos equivalentes são ambíguos', () => {
    const exact = reconcileItems([item('2026-06-10', -10, 'card_purchase', 'OUTRA DESCRICAO')], [tx('a', '2026-06-10')]);
    expect(exact.statement[0].matchType).toBe('exact_match');
    const ambiguous = reconcileItems([item('2026-06-10')], [tx('a', '2026-06-10'), tx('b', '2026-06-10')]);
    expect(ambiguous.statement[0].matchType).toBe('ambiguous');
    expect(ambiguous.statement[0].candidates).toEqual(['a', 'b']);
  });

  it('é um-para-um por ocorrência, estável, e não associa compra a estorno', () => {
    const repeated = reconcileItems([item('2026-06-10'), item('2026-06-10')], [tx('b', '2026-06-10'), tx('a', '2026-06-10')]);
    expect(repeated.statement.map((r) => r.transaction?.id)).toEqual(['a', 'b']);
    const credit = reconcileItems([item('2026-06-10', 10, 'card_credit')], [tx('expense', '2026-06-10')]);
    expect(credit.statement[0].matchType).toBe('statement_only');
  });

  it('lançamento pago vale pelo valor pago; previsto continua valendo pelo previsto', () => {
    // Baixa de dívida em que a parcela prevista (790) foi quitada por 890,
    // porque uma compra extra foi paga junto. O extrato traz um débito único de
    // 890 — é o valor que saiu da conta, e é ele que precisa casar.
    const baixa = {
      id: 'baixa', competence_date: '2026-08-01', type: 'expense', version: 1,
      description: 'Pagamento Mimo (7/24)', status: 'paid',
      amount: 890, amount_planned: 790,
    };
    expect(transactionEffectCents(baixa)).toBe(89000);

    const extrato = {
      date: '2026-08-01', amount: -890, amount_cents: toCents(-890),
      kind: 'debit', description: 'MIMO MOVEIS UBIRATA BRA',
    };
    const conciliado = reconcileItems([extrato], [baixa]);
    expect(conciliado.statement[0].matchType).toBe('exact_match');
    expect(conciliado.statement[0].transaction.id).toBe('baixa');
    expect(conciliado.hopecashOnly).toHaveLength(0);

    // Previsto ainda não movimentou a conta: continua valendo pelo planejado.
    const previsto = {
      id: 'previsto', competence_date: '2026-08-01', type: 'expense', version: 1,
      description: 'ALUGUEL', status: 'planned', amount: null, amount_planned: 1200,
    };
    expect(transactionEffectCents(previsto)).toBe(120000);
  });

  it('no ciclo informado, a data da compra ordena mas não exclui candidatos', () => {
    // A fatura traz a data da compra (30/06); o lançamento à mão foi digitado
    // com a competência do vencimento (01/08). Ambos são do mesmo ciclo.
    const compra = item('2026-06-30', -331.03, 'card_purchase', 'PARAN SUPERMERCADOS UB');
    const lancado = tx('c1', '2026-08-01', 331.03, 'expense', 'PARAN SUPERMERCADOS UB');
    expect(reconcileItems([compra], [lancado]).statement[0].matchType).toBe('statement_only');

    const bound = reconcileItems([compra], [lancado], { cycleBound: true });
    expect(bound.statement[0].matchType).toBe('probable_match');
    expect(bound.statement[0].confidence).toBeGreaterThan(0);
    expect(bound.hopecashOnly).toHaveLength(0);

    // Valor em centavos e tipo continuam obrigatórios dentro do ciclo.
    const outroValor = tx('c2', '2026-08-01', 331.04, 'expense', 'PARAN SUPERMERCADOS UB');
    expect(reconcileItems([compra], [outroValor], { cycleBound: true }).statement[0].matchType).toBe('statement_only');

    // Dois lançamentos de mesmo valor no ciclo: a descrição decide.
    const outraLoja = tx('c3', '2026-08-01', 331.03, 'expense', 'OUTRA LOJA QUALQUER');
    const escolhido = reconcileItems([compra], [outraLoja, lancado], { cycleBound: true });
    expect(escolhido.statement[0].transaction.id).toBe('c1');
  });

  it('concilia parcela pela identidade parcela/total, ainda que a data seja a da compra', () => {
    // A fatura repete 30/03 em todas as 12 parcelas; a parcela lançada no
    // HopeCash tem a competência do próprio ciclo, meses à frente.
    const purchase = {
      ...item('2026-03-30', -93.07, 'card_purchase', 'G GUIDOLIN LTDA'),
      installment_number: 4, installment_total: 12,
    };
    const parcel = {
      ...tx('p4', '2026-08-01', 93.07, 'expense', 'G GUIDOLIN LTDA (4/12)'),
      installment_number: 4, installment_total: 12,
    };
    const matched = reconcileItems([purchase], [parcel]);
    expect(matched.statement[0].matchType).toBe('probable_match');
    expect(matched.statement[0].reason).toMatch(/parcela 4\/12/);
    expect(matched.hopecashOnly).toHaveLength(0);

    // Outra parcela da mesma série, de mesmo valor, não assume o lugar da 4.
    const other = { ...parcel, id: 'p5', installment_number: 5 };
    expect(reconcileItems([purchase], [other]).statement[0].matchType).toBe('statement_only');
  });

  it('processa faturas extensas e bloqueia diferença de um centavo', () => {
    const many = Array.from({ length: 501 }, (_, i) => item('2026-06-10', -10, 'card_purchase', `Compra ${i}`));
    const result = reconcileItems(many, []);
    expect(result.statement).toHaveLength(501);
    const summary = reconciliationSummary(
      { official_total_cents: 1001, current_total_cents: 1000, recognized_total_cents: 1001 },
      [],
    );
    expect(summary.difference_cents).toBe(1);
    expect(summary.can_complete).toBe(false);
  });
});

describe('Importação de extrato', () => {
  // Cada upload usa uma conta própria para isolar as janelas de conciliação.
  const newAccount = async () => (await api.post('/api/v1/accounts').set(auth(token))
    .send({ name: `Conta ${Math.random().toString(36).slice(2, 8)}`, type: 'checking' })).body.data.id;

  it('importa CSV com detecção de colunas, aplica regra de categoria e confirma após decisões', async () => {
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('account_id', accountId)
      .attach('file', Buffer.from(CSV, 'utf-8'), 'extrato.csv');
    expect(upload.status).toBe(201);
    const { batch, items, summary } = upload.body.data;
    expect(batch.import_kind).toBe('bank_statement');
    expect(items).toHaveLength(3);
    expect(summary).toBeTruthy();
    // Sem transações prévias na conta: tudo é "somente no extrato" e pede decisão.
    expect(items.every((i) => i.match_type === 'statement_only' && !i.decision)).toBe(true);

    const market = items.find((i) => i.description.includes('SUPERMERCADO'));
    expect(market.amount).toBe(-152.3);
    expect(market.kind).toBe('debit');
    expect(market.suggested_category_id).toBe(categoryId);

    // Categoria para o posto (a regra só cobre supermercado).
    const postoCat = await api.post('/api/v1/categories').set(auth(token))
      .send({ name: 'Posto Teste', type: 'expense' });
    for (const item of items) {
      const category = item.kind === 'credit'
        ? null
        : (item.suggested_category_id ?? postoCat.body.data.id);
      await api.put(`/api/v1/imports/${batch.id}/items/${item.id}`).set(auth(token))
        .send({ decision: 'create', ...(category ? { suggested_category_id: category } : {}) });
    }

    const confirm = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.imported).toBe(3);
    expect(confirm.body.data.created).toBe(3);
    expect(confirm.body.data.difference_cents).toBeNull(); // sem total oficial

    const txs = await api.get(`/api/v1/transactions?account_id=${accountId}`).set(auth(token));
    expect(txs.body.data.length).toBe(3);
    const imported = txs.body.data.find((t) => t.description.includes('SUPERMERCADO'));
    expect(imported.type).toBe('expense');
    expect(imported.status).toBe('paid');
    expect(Number(imported.amount)).toBe(152.3);
    expect(imported.category_id).toBe(categoryId);
  });

  it('reconhece reimportação (OFX) como correspondência e não duplica ao confirmar', async () => {
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'ofx')
      .field('account_id', accountId)
      .attach('file', Buffer.from(OFX, 'utf-8'), 'extrato.ofx');
    expect(upload.status).toBe(201);
    const { batch, items } = upload.body.data;
    // 2 itens do OFX casam com a importação anterior; a transação POSTO (03/07)
    // fica na janela como "somente no HopeCash".
    const statement = items.filter((i) => i.item_origin === 'statement');
    expect(statement).toHaveLength(2);
    expect(statement.every((i) => i.match_type === 'exact_match' && i.decision === 'match')).toBe(true);
    const hopecash = items.filter((i) => i.item_origin === 'hopecash');
    expect(hopecash.map((i) => i.description)).toContain('POSTO SHELL');

    for (const item of hopecash) {
      await api.put(`/api/v1/imports/${batch.id}/items/${item.id}`).set(auth(token))
        .send({ decision: 'keep' });
    }
    const confirm = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.created).toBe(0);
    expect(confirm.body.data.imported).toBe(0);

    const txs = await api.get(`/api/v1/transactions?account_id=${accountId}`).set(auth(token));
    expect(txs.body.data.length).toBe(3); // sem duplicatas
  });

  it('permite editar descrição, data, valor e tipo de um item antes de confirmar', async () => {
    const acc = await newAccount();
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('account_id', acc)
      .attach('file', Buffer.from('Data;Descrição;Valor\n05/07/2026;TARIFA MENSAL;-29,90\n', 'utf-8'), 'x.csv');
    const { batch, items } = upload.body.data;

    const edit = await api.put(`/api/v1/imports/${batch.id}/items/${items[0].id}`)
      .set(auth(token))
      .send({ description: 'Tarifa bancária julho', item_date: '2026-07-06', amount: 31.9, kind: 'debit' });
    expect(edit.status).toBe(200);
    expect(edit.body.data.item.description).toBe('Tarifa bancária julho');
    expect(edit.body.data.item.item_date).toBe('2026-07-06');
    expect(Number(edit.body.data.item.amount)).toBe(-31.9); // sinal segue o kind

    const cat = await api.post('/api/v1/categories').set(auth(token))
      .send({ name: 'Tarifas', type: 'expense' });
    await api.put(`/api/v1/imports/${batch.id}/items/${items[0].id}`).set(auth(token))
      .send({ decision: 'create', suggested_category_id: cat.body.data.id });

    const confirm = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(confirm.body.data.created).toBe(1);
    const txs = await api.get(`/api/v1/transactions?account_id=${acc}`).set(auth(token));
    const tx = txs.body.data.find((t) => t.description === 'Tarifa bancária julho');
    expect(tx.competence_date).toBe('2026-07-06');
    expect(Number(tx.amount)).toBe(31.9);
  });

  it('permite editar categoria e subcategoria de um item no grid e confirma com ambas no lançamento', async () => {
    const acc = await newAccount();
    const sub = await api.post('/api/v1/categories/subcategories').set(auth(token))
      .send({ name: 'Hortifruti', category_id: categoryId });
    expect(sub.status).toBe(201);

    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('account_id', acc)
      .attach('file', Buffer.from('Data;Descrição;Valor\n05/07/2026;FEIRA LIVRE;-45,00\n', 'utf-8'), 'y.csv');
    const { batch, items } = upload.body.data;

    const patched = await api.put(`/api/v1/imports/${batch.id}/items/${items[0].id}`)
      .set(auth(token))
      .send({ suggested_category_id: categoryId, suggested_subcategory_id: sub.body.data.id });
    expect(patched.status).toBe(200);
    expect(patched.body.data.item.suggested_category_id).toBe(categoryId);
    expect(patched.body.data.item.suggested_subcategory_id).toBe(sub.body.data.id);

    await api.put(`/api/v1/imports/${batch.id}/items/${items[0].id}`).set(auth(token))
      .send({ decision: 'create' });
    const confirm = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(confirm.body.data.created).toBe(1);
    const txs = await api.get(`/api/v1/transactions?account_id=${acc}`).set(auth(token));
    const tx = txs.body.data.find((t) => t.description === 'FEIRA LIVRE');
    expect(tx.category_id).toBe(categoryId);
    expect(tx.subcategory_id).toBe(sub.body.data.id);
  });

  it('mostra como "somente no HopeCash" só transações pagas (planejadas ficam de fora)', async () => {
    const acc = await newAccount();
    await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'CONTA AGUA', amount_planned: 120, competence_date: '2026-07-10',
      status: 'paid', account_id: acc, category_id: categoryId,
    });
    await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'CONTA LUZ', amount_planned: 85, competence_date: '2026-07-11',
      status: 'planned', account_id: acc, category_id: categoryId,
    });
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('account_id', acc)
      .attach('file', Buffer.from('Data;Descrição;Valor\n10/07/2026;PADARIA;-15,00\n11/07/2026;FARMACIA;-30,00\n', 'utf-8'), 'z.csv');
    const { items } = upload.body.data;
    const hopecash = items.filter((i) => i.item_origin === 'hopecash');
    expect(hopecash.map((i) => i.description)).toEqual(['CONTA AGUA']);
    expect(hopecash.some((i) => i.description === 'CONTA LUZ')).toBe(false);
  });

  it('exige categoria para criar despesa, mas crédito passa sem', async () => {
    const acc = await newAccount();
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('account_id', acc)
      .attach('file', Buffer.from('Data;Descrição;Valor\n20/07/2026;PADARIA;-15,00\n21/07/2026;PIX RECEBIDO;40,00\n', 'utf-8'), 'w.csv');
    const { batch, items } = upload.body.data;
    const debit = items.find((i) => i.kind === 'debit');
    const credit = items.find((i) => i.kind === 'credit');
    await api.put(`/api/v1/imports/${batch.id}/items/${debit.id}`).set(auth(token)).send({ decision: 'create' });
    await api.put(`/api/v1/imports/${batch.id}/items/${credit.id}`).set(auth(token)).send({ decision: 'create' });

    const blocked = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(blocked.status).toBe(400);

    await api.put(`/api/v1/imports/${batch.id}/items/${debit.id}`).set(auth(token))
      .send({ suggested_category_id: categoryId });
    const ok = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(ok.status).toBe(200);
    expect(ok.body.data.created).toBe(2);
  });

  it('permite concluir extrato sem total oficial, com todas as decisões', async () => {
    const acc = await newAccount();
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('account_id', acc)
      .attach('file', Buffer.from('Data;Descrição;Valor\n22/07/2026;BARBEARIA;-60,00\n', 'utf-8'), 'v.csv');
    const { batch, items, summary } = upload.body.data;
    expect(summary.can_complete).toBe(false); // item sem decisão
    await api.put(`/api/v1/imports/${batch.id}/items/${items[0].id}`).set(auth(token))
      .send({ decision: 'create', suggested_category_id: categoryId });
    const confirm = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.created).toBe(1);
    expect(confirm.body.data.difference_cents).toBeNull();
  });

  it('reanálise preserva associação manual', async () => {
    const acc = await newAccount();
    // Duas transações idênticas no mesmo dia: o item do arquivo fica ambíguo.
    const a = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'ESCOLA KIDS', amount_planned: 300, competence_date: '2026-07-25',
      status: 'planned', account_id: acc, category_id: categoryId,
    });
    const b = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'ESCOLA KIDS', amount_planned: 300, competence_date: '2026-07-25',
      status: 'paid', account_id: acc, category_id: categoryId,
    });
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('account_id', acc)
      .attach('file', Buffer.from('Data;Descrição;Valor\n25/07/2026;ESCOLA KIDS;-300,00\n', 'utf-8'), 'u.csv');
    const { batch, items } = upload.body.data;
    const item = items.find((i) => i.item_origin === 'statement');
    expect(item.match_type).toBe('ambiguous');

    await api.put(`/api/v1/imports/${batch.id}/items/${item.id}`).set(auth(token))
      .send({ decision: 'match', matched_transaction_id: b.body.data.id });

    const re = await api.post(`/api/v1/imports/${batch.id}/analyze`).set(auth(token));
    expect(re.status).toBe(200);
    const after = re.body.data.items.find((i) => i.id === item.id);
    expect(after.matched_transaction_id).toBe(b.body.data.id);
    expect(after.decision_payload.manual_match).toBe(true);
    // A planejada restante não vira "somente no HopeCash" em conta.
    expect(re.body.data.items.some((i) => i.description === 'ESCOLA KIDS' && i.item_origin === 'hopecash')).toBe(false);
  });

  it('aceita total oficial opcional e lança a diferença restante', async () => {
    const acc = await newAccount();
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('account_id', acc)
      .attach('file', Buffer.from('Data;Descrição;Valor\n27/07/2026;ALMOCO;-45,00\n', 'utf-8'), 't.csv');
    const { batch, items } = upload.body.data;
    const item = items[0];

    // Decide o item e então informa o total oficial (R$ 50), sobrando R$ 5.
    await api.put(`/api/v1/imports/${batch.id}/items/${item.id}`).set(auth(token))
      .send({ decision: 'create', suggested_category_id: categoryId });
    const setTotal = await api.put(`/api/v1/imports/${batch.id}/official-total`).set(auth(token))
      .send({ official_total_cents: 5000 });
    expect(setTotal.body.data.summary.difference_cents).toBe(500);

    const diff = await api.post(`/api/v1/imports/${batch.id}/difference-item`).set(auth(token));
    expect(diff.status).toBe(200);
    const ajuste = diff.body.data.items.find((i) => i.description === 'Ajuste de diferença da fatura');
    await api.put(`/api/v1/imports/${batch.id}/items/${ajuste.id}`).set(auth(token))
      .send({ decision: 'create', suggested_category_id: categoryId });

    const confirm = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.created).toBe(2);
    expect(confirm.body.data.difference_cents).toBe(0);
  });

  it('é idempotente por hash do arquivo', async () => {
    const acc = await newAccount();
    const buf = Buffer.from('Data;Descrição;Valor\n28/07/2026;ACADEMIA;-99,90\n', 'utf-8');
    const first = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('account_id', acc).attach('file', buf, 'idem.csv');
    expect(first.status).toBe(201);
    const second = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('account_id', acc).attach('file', buf, 'idem.csv');
    expect(second.status).toBe(200);
    expect(second.body.idempotent).toBe(true);
    expect(second.body.data.batch.id).toBe(first.body.data.batch.id);
  });

  it('concilia baixa de dívida cujo valor pago difere do previsto', async () => {
    // Regressão: a parcela prevista era 790, mas foram pagos 890 (uma compra
    // extra quitada junto). O app grava amount=890 e amount_planned=790. O
    // extrato traz um único débito de 890 — antes a conciliação comparava pelo
    // previsto e a baixa nunca casava, sobrando como "somente no HopeCash".
    const acc = await newAccount();
    await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'Pagamento Mimo (7/24)',
      amount_planned: 790, amount: 890, competence_date: '2026-08-01',
      payment_date: '2026-08-01', status: 'paid', account_id: acc,
      category_id: categoryId,
    });
    const csv = 'Data;Descrição;Valor\n01/08/2026;MIMO MOVEIS UBIRATA BRA;-890,00\n';
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('account_id', acc)
      .attach('file', Buffer.from(csv, 'utf-8'), 'extrato-mimo.csv');
    expect(upload.status).toBe(201);

    const { items } = upload.body.data;
    const statement = items.filter((i) => i.item_origin === 'statement');
    expect(statement).toHaveLength(1);
    expect(statement[0].match_type).toBe('exact_match');
    expect(statement[0].decision).toBe('match');
    // A baixa foi reconhecida: não sobra pendência "somente no HopeCash".
    expect(items.filter((i) => i.item_origin === 'hopecash')).toHaveLength(0);
  });

  it('quita dívida escolhida na revisão: baixa o saldo e liga o lançamento à dívida', async () => {
    const acc = await newAccount();
    const debt = (await api.post('/api/v1/debts').set(auth(token)).send({
      name: 'Empréstimo Teste', original_amount: 2400, outstanding_balance: 2400,
      total_installments: 12, paid_installments: 0, installment_amount: 200,
      due_day: 10, category_id: categoryId,
    })).body.data;
    const csv = 'Data;Descrição;Valor\n10/08/2026;PARCELA EMPRESTIMO BANCO;-200,00\n';
    const { batch, items } = (await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('account_id', acc)
      .attach('file', Buffer.from(csv, 'utf-8'), 'extrato-divida.csv')).body.data;

    const item = items.find((i) => i.item_origin === 'statement');
    const patched = await api.put(`/api/v1/imports/${batch.id}/items/${item.id}`).set(auth(token))
      .send({ decision: 'create', settlement_type: 'debt', settlement_id: debt.id });
    expect(patched.status).toBe(200);
    expect(patched.body.data.item.decision_payload.settlement_id).toBe(debt.id);

    expect((await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token))).status).toBe(200);
    const after = (await api.get(`/api/v1/debts/${debt.id}`).set(auth(token))).body.data;
    expect(Number(after.outstanding_balance)).toBe(2200);
    expect(after.paid_installments).toBe(1);
    const tx = (await api.get(`/api/v1/transactions?account_id=${acc}`).set(auth(token)))
      .body.data.find((t) => t.description.includes('EMPRESTIMO'));
    expect(tx.notes).toContain(`"debt_id":"${debt.id}"`);
    expect(tx.category_id).toBe(categoryId);
  });

  it('quita fatura escolhida na revisão: marca as compras do ciclo como pagas', async () => {
    const acc = await newAccount();
    const card = (await api.post('/api/v1/cards').set(auth(token))
      .send({ name: 'Cartão Quitação', limit_amount: 5000, closing_day: 25, due_day: 10 })).body.data;
    const purchase = (await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'COMPRA CARTAO', amount_planned: 300,
      competence_date: '2026-07-20', due_date: '2026-08-10', status: 'planned',
      card_id: card.id, category_id: categoryId,
    })).body.data;
    const csv = 'Data;Descrição;Valor\n10/08/2026;PAGTO FATURA CARTAO;-300,00\n';
    const { batch, items } = (await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('account_id', acc)
      .attach('file', Buffer.from(csv, 'utf-8'), 'extrato-fatura.csv')).body.data;

    const item = items.find((i) => i.item_origin === 'statement');
    // Liquidação de fatura não exige categoria: o gasto já foi contado na compra.
    await api.put(`/api/v1/imports/${batch.id}/items/${item.id}`).set(auth(token))
      .send({ decision: 'create', settlement_type: 'card', settlement_id: card.id });
    expect((await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token))).status).toBe(200);

    const paid = (await api.get(`/api/v1/transactions/${purchase.id}`).set(auth(token))).body.data;
    expect(paid.status).toBe('paid');
    expect(paid.payment_date).toBe('2026-08-10');
    const settlement = (await api.get(`/api/v1/transactions?account_id=${acc}`).set(auth(token)))
      .body.data.find((t) => t.description.includes('PAGTO FATURA'));
    expect(settlement.card_id).toBe(card.id);
    expect(settlement.account_id).toBe(acc);
  });

  it('recusa quitação em crédito do extrato', async () => {
    const acc = await newAccount();
    const debt = (await api.post('/api/v1/debts').set(auth(token)).send({
      name: 'Dívida Crédito', original_amount: 100, outstanding_balance: 100,
      total_installments: 1, installment_amount: 100,
    })).body.data;
    const csv = 'Data;Descrição;Valor\n05/08/2026;PIX RECEBIDO;300,00\n';
    const { batch, items } = (await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('account_id', acc)
      .attach('file', Buffer.from(csv, 'utf-8'), 'extrato-credito.csv')).body.data;
    const res = await api.put(`/api/v1/imports/${batch.id}/items/${items[0].id}`).set(auth(token))
      .send({ settlement_type: 'debt', settlement_id: debt.id });
    expect(res.status).toBe(400);
  });

  it('converte lote de extrato antigo (sem janela) ao reabrir, com backfill', async () => {
    const acc = await newAccount();
    await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'ALUGUEL ANTIGO', amount_planned: 1000, amount: 1000,
      competence_date: '2026-07-15', status: 'paid', account_id: acc, category_id: categoryId,
    });
    const ts = now();
    const batchId = crypto.randomUUID();
    await db('import_batches').insert({
      id: batchId, user_id: userId, created_at: ts, updated_at: ts, version: 1,
      source: 'csv', file_name: 'legado.csv', import_kind: 'bank_statement', account_id: acc,
      status: 'reviewing', total_items: 1, imported_items: 0, reconciliation_status: 'reviewing',
    });
    await db('import_items').insert({
      id: crypto.randomUUID(), user_id: userId, batch_id: batchId, created_at: ts, updated_at: ts, version: 1,
      item_origin: 'statement', item_date: '2026-07-15', description: 'ALUGUEL ANTIGO',
      amount: -1000, amount_cents: -100000, kind: 'debit', status: 'pending',
    });
    const res = await api.get(`/api/v1/imports/${batchId}`).set(auth(token));
    expect(res.body.backfilled).toBe(true);
    const { batch, items } = res.body.data;
    expect(batch.period_start).toBe('2026-07-12');
    expect(batch.period_end).toBe('2026-07-18');
    const item = items.find((i) => i.item_origin === 'statement');
    expect(item.match_type).toBe('exact_match');
    expect(item.decision).toBe('match');
  });
});

describe('Importação de fatura de cartão', () => {
  it('exige card_id para fatura', async () => {
    const res = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('import_kind', 'credit_card_invoice')
      .attach('file', Buffer.from(INVOICE_CSV, 'utf-8'), 'fatura.csv');
    expect(res.status).toBe(400);
  });

  it('analisa bidirecionalmente, exige decisões/categoria e conclui somente em zero', async () => {
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('import_kind', 'credit_card_invoice')
      .field('card_id', cardId)
      .field('invoice_due_date', '2026-07-05')
      .field('reference_month', '2026-06-01')
      .attach('file', Buffer.from(INVOICE_CSV, 'utf-8'), 'fatura.csv');
    expect(upload.status).toBe(201);
    const { batch, items } = upload.body.data;
    expect(batch.import_kind).toBe('credit_card_invoice');
    expect(batch.card_id).toBe(cardId);
    expect(batch.official_total_cents).toBe(20720);
    expect(items).toHaveLength(3); // sem linhas de resumo
    expect(upload.body.data.summary.difference_cents).toBe(20720);
    expect(items.every((i) => i.match_type === 'statement_only')).toBe(true);
    const market = items.find((i) => i.description.includes('SUPERMERCADO'));
    expect(market.kind).toBe('card_purchase');
    expect(market.suggested_category_id).toBe(categoryId);

    const blocked = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(blocked.status).toBe(400);
    const decisions = await api.post(`/api/v1/imports/${batch.id}/decisions/bulk`).set(auth(token)).send({
      item_ids: items.map((i) => i.id), decision: 'create', suggested_category_id: categoryId,
    });
    expect(decisions.status).toBe(200);
    expect(decisions.body.data.summary.projected_total_cents).toBe(20720);
    expect(decisions.body.data.summary.can_complete).toBe(true);
    const confirm = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.created).toBe(3);
    expect(confirm.body.data.difference_cents).toBe(0);

    const txs = await api.get(`/api/v1/transactions?card_id=${cardId}`).set(auth(token));
    expect(txs.body.data.length).toBe(3);
    for (const tx of txs.body.data) {
      expect(tx.card_id).toBe(cardId);
      expect(tx.account_id).toBeFalsy(); // não afeta saldo de conta
      expect(tx.status).toBe('planned');
      expect(tx.due_date).toBe('2026-07-05');
    }
    const purchase = txs.body.data.find((t) => t.description.includes('IFOOD'));
    expect(purchase.type).toBe('expense');
    expect(Number(purchase.amount_planned)).toBe(89.9);
    expect(purchase.competence_date).toBe('2026-06-12');
    const refund = txs.body.data.find((t) => t.description.includes('ESTORNO'));
    expect(refund.type).toBe('income');
    expect(Number(refund.amount_planned)).toBe(35);

    const retry = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(retry.status).toBe(200);
    expect(retry.body.data.idempotent).toBe(true);
  });

  it('upload repetido retoma o mesmo lote sem duplicar', async () => {
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('import_kind', 'credit_card_invoice')
      .field('card_id', cardId)
      .attach('file', Buffer.from(INVOICE_CSV, 'utf-8'), 'fatura2.csv');
    expect(upload.status).toBe(200);
    expect(upload.body.idempotent).toBe(true);
    expect(upload.body.data.batch.status).toBe('confirmed');
  });

  it('arquivo sem total exige confirmação manual e diferença de centavo bloqueia', async () => {
    const csv = 'date,title,amount\n2026-07-01,PADARIA UNICA,25.00\n';
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('import_kind', 'credit_card_invoice')
      .field('card_id', cardId)
      .attach('file', Buffer.from(csv, 'utf-8'), 'sem-total.csv');
    const { batch, items } = upload.body.data;
    expect(batch.official_total_cents).toBeNull();
    expect(batch.invoice_due_date).toBe('2026-08-05');
    await api.put(`/api/v1/imports/${batch.id}/items/${items[0].id}`).set(auth(token)).send({
      decision: 'create', suggested_category_id: categoryId,
    });
    await api.put(`/api/v1/imports/${batch.id}/official-total`).set(auth(token)).send({ official_total_cents: 2501 });
    expect((await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token))).status).toBe(400);
    const total = await api.put(`/api/v1/imports/${batch.id}/official-total`).set(auth(token)).send({ official_total_cents: 2500 });
    expect(total.body.data.summary.can_complete).toBe(true);
    expect((await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token))).status).toBe(200);
  });

  it('lança a diferença remanescente em um novo item para permitir concluir a conciliação', async () => {
    // Conteúdo e ciclo distintos dos demais testes desta suíte para não colidir com o
    // cache de upload idempotente (mesmo hash de arquivo) nem com transações já confirmadas.
    const diffInvoiceCsv = `date,title,amount
2026-10-12,IFOOD RESTAURANTE DIF,89.90
2026-10-15,SUPERMERCADO BOM PRECO DIF,152.30
2026-10-20,ESTORNO LOJA XYZ DIF,-35.00
2026-10-30,Total da fatura,207.20
2026-10-30,Pagamento mínimo,50.00
`;
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('import_kind', 'credit_card_invoice')
      .field('card_id', cardId)
      .field('invoice_due_date', '2026-11-05')
      .attach('file', Buffer.from(diffInvoiceCsv, 'utf-8'), 'fatura-diferenca.csv');
    const { batch, items } = upload.body.data;
    expect(upload.body.data.summary.difference_cents).toBe(20720);

    // Decide apenas dois dos três itens, deixando uma diferença de R$ 89,90 (o item IFOOD).
    const market = items.find((i) => i.description.includes('SUPERMERCADO'));
    const refund = items.find((i) => i.description.includes('ESTORNO'));
    const ifood = items.find((i) => i.description.includes('IFOOD'));
    await api.put(`/api/v1/imports/${batch.id}/items/${market.id}`).set(auth(token))
      .send({ decision: 'create', suggested_category_id: categoryId });
    await api.put(`/api/v1/imports/${batch.id}/items/${refund.id}`).set(auth(token))
      .send({ decision: 'create' });
    const ignoreIfood = await api.put(`/api/v1/imports/${batch.id}/items/${ifood.id}`).set(auth(token))
      .send({ decision: 'ignore' });
    expect(ignoreIfood.body.data.summary.difference_cents).toBe(8990);
    expect(ignoreIfood.body.data.summary.can_complete).toBe(false);

    const added = await api.post(`/api/v1/imports/${batch.id}/difference-item`).set(auth(token));
    expect(added.status).toBe(200);
    expect(added.body.data.summary.difference_cents).toBe(8990); // item ainda pendente de decisão
    const adjustment = added.body.data.items.find((i) => i.description === 'Ajuste de diferença da fatura');
    expect(adjustment).toBeTruthy();
    expect(adjustment.kind).toBe('card_purchase');
    expect(Number(adjustment.amount)).toBeCloseTo(-89.9);

    const duplicate = await api.post(`/api/v1/imports/${batch.id}/difference-item`).set(auth(token));
    expect(duplicate.status).toBe(409); // já existe ajuste pendente

    const decided = await api.put(`/api/v1/imports/${batch.id}/items/${adjustment.id}`).set(auth(token))
      .send({ decision: 'create', suggested_category_id: categoryId });
    expect(decided.body.data.summary.difference_cents).toBe(0);
    expect(decided.body.data.summary.can_complete).toBe(true);

    const confirm = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.difference_cents).toBe(0);
  });

  it('associa lançamento existente, detecta alteração concorrente e permite retomar cancelamento', async () => {
    const existing = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'ACADEMIA FIT', amount_planned: 80,
      competence_date: '2026-08-10', due_date: '2026-09-05', status: 'planned',
      card_id: cardId, category_id: categoryId,
    });
    expect(existing.status).toBe(201);
    const csv = 'date,title,amount\n2026-08-10,ACADEMIA FIT,80.00\n2026-08-31,Total da fatura,80.00\n';
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('import_kind', 'credit_card_invoice').field('card_id', cardId)
      .field('invoice_due_date', '2026-09-05').attach('file', Buffer.from(csv), 'academia.csv');
    expect(upload.body.data.items[0].match_type).toBe('exact_match');
    expect(upload.body.data.summary.can_complete).toBe(true);
    await api.put(`/api/v1/transactions/${existing.body.data.id}`).set(auth(token)).send({ notes: 'alterada em outro dispositivo' });
    const conflictResult = await api.post(`/api/v1/imports/${upload.body.data.batch.id}/confirm`).set(auth(token));
    expect(conflictResult.status).toBe(409);

    const cancelUpload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('import_kind', 'credit_card_invoice').field('card_id', cardId)
      .attach('file', Buffer.from('date,title,amount\n2026-09-01,TESTE CANCELAR,1.00\n'), 'cancelar.csv');
    const cancel = await api.post(`/api/v1/imports/${cancelUpload.body.data.batch.id}/cancel`).set(auth(token));
    expect(cancel.body.data.status).toBe('canceled');
    const resume = await api.post(`/api/v1/imports/${cancelUpload.body.data.batch.id}/resume`).set(auth(token));
    expect(resume.body.data.batch.status).toBe('reviewing');
  });

  it('detecta parcelamento na descrição e lança as parcelas futuras ao concluir', async () => {
    expect(detectInstallment('NOTEBOOK MAGAZINE 2/5')).toMatchObject({ number: 2, total: 5 });
    expect(detectInstallment('LOJA ABC (3/12)')).toMatchObject({ number: 3, total: 12 });
    expect(detectInstallment('MOVEIS PARC 03/10')).toMatchObject({ number: 3, total: 10 });
    expect(detectInstallment('CURSO PARCELA 2 de 4')).toMatchObject({ number: 2, total: 4 });
    expect(detectInstallment('PADARIA 12/06')).toBeNull(); // data, não parcela (12 > 6)
    expect(detectInstallment('COMPRA AVULSA')).toBeNull();

    const csv = 'date,title,amount\n2026-12-10,NOTEBOOK MAGAZINE 2/5,500.00\n2026-12-31,Total da fatura,500.00\n';
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('import_kind', 'credit_card_invoice')
      .field('card_id', cardId)
      .field('invoice_due_date', '2027-01-05')
      .attach('file', Buffer.from(csv, 'utf-8'), 'fatura-parcelada.csv');
    expect(upload.status).toBe(201);
    const item = upload.body.data.items[0];
    expect(item.installment_number).toBe(2);
    expect(item.installment_total).toBe(5);

    await api.put(`/api/v1/imports/${upload.body.data.batch.id}/items/${item.id}`).set(auth(token))
      .send({ decision: 'create', suggested_category_id: categoryId });
    const confirm = await api.post(`/api/v1/imports/${upload.body.data.batch.id}/confirm`).set(auth(token));
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.created).toBe(1);
    expect(confirm.body.data.future_installments).toBe(3);
    expect(confirm.body.data.difference_cents).toBe(0);

    const txs = await api.get(`/api/v1/transactions?card_id=${cardId}`).set(auth(token));
    const group = txs.body.data
      .filter((t) => t.installment_total === 5)
      .sort((a, b) => a.installment_number - b.installment_number);
    expect(group).toHaveLength(4); // parcela atual (2/5) + 3 futuras
    expect(group.map((t) => t.installment_number)).toEqual([2, 3, 4, 5]);
    expect(new Set(group.map((t) => t.installment_group_id)).size).toBe(1);
    expect(group[0].installment_group_id).toBeTruthy();
    expect(group.map((t) => t.due_date)).toEqual(['2027-01-05', '2027-02-05', '2027-03-05', '2027-04-05']);
    expect(group.map((t) => t.competence_date)).toEqual(['2026-12-10', '2027-01-10', '2027-02-10', '2027-03-10']);
    for (const t of group) {
      expect(Number(t.amount_planned)).toBe(500);
      expect(t.status).toBe('planned');
      expect(t.category_id).toBe(categoryId);
    }
    expect(group[1].description).toContain('(3/5)');
    expect(group[3].description).toContain('(5/5)');
  });

  it('fatura do C6 em Latin-1 concilia parcela lançada manualmente e ignora o pagamento', async () => {
    // Parcela 4/12 já lançada à mão no ciclo, com a competência do vencimento —
    // é o caso que a data de compra repetida da fatura nunca alcançaria.
    const manual = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'G GUIDOLIN LTDA (4/12)', amount_planned: 93.07,
      competence_date: '2026-08-05', due_date: '2026-08-05', status: 'planned',
      card_id: cardId, category_id: categoryId, installment_number: 4, installment_total: 12,
    });
    expect(manual.status).toBe(201);

    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv')
      .field('import_kind', 'credit_card_invoice')
      .field('card_id', cardId)
      .field('invoice_due_date', '2026-08-05')
      .attach('file', Buffer.from(C6_INVOICE_CSV, 'latin1'), 'Fatura_2026-08-05.csv');
    expect(upload.status).toBe(201);
    const { items } = upload.body.data;

    const statement = items.filter((i) => i.item_origin === 'statement');
    expect(statement).toHaveLength(4);
    expect(statement.some((i) => /pagamento/i.test(i.description))).toBe(false);
    // Latin-1 decodificado corretamente: acentos preservados no cabeçalho e nas descrições.
    expect(Number(statement.find((i) => i.description.includes('ANTHROPIC')).amount)).toBe(-115.45);

    const parcelada = statement.find((i) => i.description.includes('GUIDOLIN'));
    expect(parcelada.match_type).toBe('probable_match');
    expect(parcelada.matched_transaction_id).toBe(manual.body.data.id);
    expect(parcelada.installment_number).toBe(4);
    expect(items.some((i) => i.item_origin === 'hopecash'
      && i.matched_transaction_id === manual.body.data.id)).toBe(false);
  });

  it('associação traz a categoria e a subcategoria do lançamento e aplica a troca ao confirmar', async () => {
    const antiga = await api.post('/api/v1/categories').set(auth(token)).send({ name: 'Lazer Antiga', type: 'expense' });
    const nova = await api.post('/api/v1/categories').set(auth(token)).send({ name: 'Lazer Nova', type: 'expense' });
    const sub = await api.post('/api/v1/categories/subcategories').set(auth(token))
      .send({ name: 'Cinema', category_id: antiga.body.data.id });
    expect(sub.status).toBe(201);

    // Ciclo exclusivo deste teste: outros testes da suíte ocupam ciclos vizinhos
    // no mesmo cartão e entrariam na conciliação como "somente no HopeCash".
    const existing = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'CINEMA CENTRO', amount_planned: 64,
      competence_date: '2027-08-10', due_date: '2027-09-05', status: 'planned',
      card_id: cardId, category_id: antiga.body.data.id, subcategory_id: sub.body.data.id,
    });

    const csv = 'date,title,amount\n2027-08-10,CINEMA CENTRO,64.00\n2027-08-31,Total da fatura,64.00\n';
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('import_kind', 'credit_card_invoice').field('card_id', cardId)
      .field('invoice_due_date', '2027-09-05').attach('file', Buffer.from(csv, 'utf-8'), 'cinema.csv');
    const { batch, items } = upload.body.data;
    const item = items.find((i) => i.item_origin === 'statement');

    // O item associado já chega com a categoria e a subcategoria do lançamento.
    expect(item.match_type).toBe('exact_match');
    expect(item.suggested_category_id).toBe(antiga.body.data.id);
    expect(item.decision_payload.subcategory_id).toBe(sub.body.data.id);

    // "Sem categoria" também é uma alteração explícita e chega ao lançamento.
    const limpa = await api.put(`/api/v1/imports/${batch.id}/items/${item.id}`).set(auth(token))
      .send({ suggested_category_id: null });
    expect(limpa.body.data.item.decision_payload.category_id).toBeNull();

    // Trocar a categoria no item passa a valer para o lançamento associado.
    const trocada = await api.put(`/api/v1/imports/${batch.id}/items/${item.id}`).set(auth(token))
      .send({ suggested_category_id: nova.body.data.id, subcategory_id: null });
    expect(trocada.body.data.item.decision).toBe('match'); // segue associado
    const confirm = await api.post(`/api/v1/imports/${batch.id}/confirm`).set(auth(token));
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.edited).toBe(1);
    expect(confirm.body.data.created).toBe(0); // associação não duplica lançamento

    const tx = await api.get(`/api/v1/transactions/${existing.body.data.id}`).set(auth(token));
    expect(tx.body.data.category_id).toBe(nova.body.data.id);
    expect(tx.body.data.subcategory_id).toBeNull();
    expect(Number(tx.body.data.amount_planned)).toBe(64); // nada mais foi alterado
  });

  it('confirmar associação sem mexer na categoria não versiona o lançamento', async () => {
    const cat = await api.post('/api/v1/categories').set(auth(token)).send({ name: 'Assinaturas', type: 'expense' });
    const existing = await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'STREAMING MENSAL', amount_planned: 39.9,
      competence_date: '2027-10-10', due_date: '2027-11-05', status: 'planned',
      card_id: cardId, category_id: cat.body.data.id,
    });
    const versaoOriginal = existing.body.data.version;

    const csv = 'date,title,amount\n2027-10-10,STREAMING MENSAL,39.90\n2027-10-31,Total da fatura,39.90\n';
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'csv').field('import_kind', 'credit_card_invoice').field('card_id', cardId)
      .field('invoice_due_date', '2027-11-05').attach('file', Buffer.from(csv, 'utf-8'), 'streaming.csv');
    expect(upload.body.data.items[0].suggested_category_id).toBe(cat.body.data.id);

    const confirm = await api.post(`/api/v1/imports/${upload.body.data.batch.id}/confirm`).set(auth(token));
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.edited).toBe(0);
    const tx = await api.get(`/api/v1/transactions/${existing.body.data.id}`).set(auth(token));
    expect(tx.body.data.version).toBe(versaoOriginal);
    expect(tx.body.data.category_id).toBe(cat.body.data.id);
  });

  it('PDF de fatura com texto extraível funciona fim a fim', async () => {
    const pdf = makeTextPdf([
      'FATURA DO CARTAO',
      'Total da fatura 155,00',
      '10/06 LIVRARIA CULTURA 120,00',
      '11/06 ESTORNO LOJA ABC -35,00',
    ]);
    const upload = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'pdf')
      .field('import_kind', 'credit_card_invoice')
      .field('card_id', cardId)
      .field('reference_month', '2026-06-01')
      .attach('file', pdf, 'fatura.pdf');
    expect(upload.status).toBe(201);
    const { items } = upload.body.data;
    expect(items).toHaveLength(2);
    expect(items[0].item_date).toBe('2026-06-10');
    expect(items[0].kind).toBe('card_purchase');
    expect(items[1].kind).toBe('card_credit');
  });

  it('PDF escaneado retorna erro amigável', async () => {
    const res = await api.post('/api/v1/imports').set(auth(token))
      .field('source', 'pdf')
      .field('import_kind', 'credit_card_invoice')
      .field('card_id', cardId)
      .attach('file', Buffer.from('%PDF-1.4\n%%EOF', 'latin1'), 'scan.pdf');
    expect(res.status).toBe(400);
    expect(res.body.error.message).toMatch(/selecionável/i);
  });
});
