import { describe, it, expect, beforeAll } from 'vitest';
import { makeApp, registerUser, auth } from './helpers.js';
import { today, addDays, addMonths, monthStart } from '../src/utils/time.js';

let api;
let token;
let accountId;
let cardId;
let expenseCategoryId;
let incomeCategoryId;
let budgetId;
let debtId;
let debtVersion;

/** Chama uma tool via protocolo MCP (tools/call) e normaliza a resposta JSON-RPC
 *  para o formato { status, body: { data } | { error: { message, details } } }
 *  que os testes abaixo já esperavam do antigo endpoint de debug /ai/tools/:name. */
async function callToolAs(bearerToken, name, args = {}) {
  const res = await api.post('/api/v1/ai/mcp/methods').set(auth(bearerToken)).send({
    jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args },
  });
  if (res.body.error) {
    return { status: res.status, body: { error: { message: res.body.error.message, details: res.body.error.data ?? null } } };
  }
  return { status: res.status, body: { data: JSON.parse(res.body.result.content[0].text) } };
}
const callTool = (name, args = {}) => callToolAs(token, name, args);

beforeAll(async () => {
  api = await makeApp();
  const user = await registerUser(api);
  token = user.access_token;

  const acc = await api.post('/api/v1/accounts').set(auth(token))
    .send({ name: 'Conta Principal', type: 'checking', initial_balance: 1000 });
  accountId = acc.body.data.id;

  const card = await api.post('/api/v1/cards').set(auth(token))
    .send({ name: 'Cartão Nubank', closing_day: 1, due_day: 10 });
  cardId = card.body.data.id;

  const expCat = await api.post('/api/v1/categories').set(auth(token))
    .send({ name: 'Mercado', type: 'expense' });
  expenseCategoryId = expCat.body.data.id;
  const incCat = await api.post('/api/v1/categories').set(auth(token))
    .send({ name: 'Salário', type: 'income' });
  incomeCategoryId = incCat.body.data.id;

  const month = today().slice(0, 7);
  await api.post('/api/v1/transactions').set(auth(token)).send({
    type: 'income', description: 'Salário de julho', amount: 5000,
    competence_date: `${month}-05`, payment_date: `${month}-05`,
    status: 'paid', account_id: accountId, category_id: incomeCategoryId,
  });
  await api.post('/api/v1/transactions').set(auth(token)).send({
    type: 'expense', description: 'Compra no mercado', amount: 300,
    competence_date: `${month}-10`, payment_date: `${month}-10`,
    status: 'paid', account_id: accountId, category_id: expenseCategoryId,
  });
  await api.post('/api/v1/transactions').set(auth(token)).send({
    type: 'expense', description: 'Conta de luz', amount_planned: 250,
    competence_date: today(), due_date: addDays(today(), 5),
    status: 'planned', account_id: accountId,
  });

  await api.post('/api/v1/goals').set(auth(token)).send({
    name: 'Viagem', target_amount: 1000, accumulated_amount: 250,
  });
  const debt = await api.post('/api/v1/debts').set(auth(token)).send({
    name: 'Financiamento carro', original_amount: 20000, outstanding_balance: 15000,
    installment_amount: 500,
  });
  debtId = debt.body.data.id;
  debtVersion = debt.body.data.version;
  await api.post('/api/v1/investments').set(auth(token)).send({
    name: 'Tesouro Selic', applied_amount: 1000, current_amount: 1050,
  });
});

describe('IA — toolbox financeira', () => {
  it('tools/list (MCP) lista o catálogo com nome, descrição e schema', async () => {
    const res = await api.post('/api/v1/ai/mcp/methods').set(auth(token))
      .send({ jsonrpc: '2.0', id: 1, method: 'tools/list' });
    expect(res.status).toBe(200);
    const tools = res.body.result.tools;
    const names = tools.map((t) => t.name);
    expect(names).toEqual(expect.arrayContaining([
      'get_balances', 'list_transactions', 'spending_by_category', 'get_budget_status',
      'get_upcoming_bills', 'get_invoices', 'get_cashflow_projection',
      'get_goals', 'get_debts', 'get_investments', 'get_month_summary',
      'search_categories', 'search_accounts',
      'create_transaction', 'update_transaction', 'pay_transaction', 'create_transfer',
      'upsert_budget_item', 'create_goal', 'add_goal_contribution', 'create_category',
    ]));
    expect(tools.some((t) => t.write === false)).toBe(true);
    expect(tools.some((t) => t.write === true)).toBe(true);
    expect(tools.every((t) => t.inputSchema.type === 'object')).toBe(true);
  });

  it('tool desconhecida devolve 404', async () => {
    const res = await callTool('nao_existe');
    expect(res.status).toBe(404);
  });

  it('get_balances soma saldo inicial + transações pagas', async () => {
    const res = await callTool('get_balances');
    expect(res.status).toBe(200);
    const acc = res.body.data.accounts.find((a) => a.id === accountId);
    expect(acc.balance).toBe(1000 + 5000 - 300);
    expect(res.body.data.total_balance).toBe(1000 + 5000 - 300);
  });

  it('list_transactions filtra por tipo e por texto', async () => {
    await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'Compra antiga no crédito', amount_planned: 42,
      competence_date: '2020-01-01', card_id: cardId,
    });
    const byType = await callTool('list_transactions', { type: 'expense' });
    expect(byType.status).toBe(200);
    expect(byType.body.data.transactions.every((t) => t.type === 'expense')).toBe(true);

    const byText = await callTool('list_transactions', { text: 'mercado' });
    expect(byText.body.data.transactions).toHaveLength(1);
    expect(byText.body.data.transactions[0].description).toBe('Compra no mercado');

    const onAnyCard = await callTool('list_transactions', { on_credit_card: true });
    expect(onAnyCard.body.data.transactions.length).toBeGreaterThan(0);
    expect(onAnyCard.body.data.transactions.every((transaction) => transaction.card_id)).toBe(true);
  });

  it('list_transactions não traz parcelas futuras por padrão, só com pedido explícito', async () => {
    await api.post('/api/v1/transactions/installments').set(auth(token)).send({
      type: 'expense', description: 'Notebook parcelado', competence_date: today(),
      total_amount: 900, installments: 3, first_due_date: addMonths(today(), 1),
      card_id: cardId,
    });

    const isInstallment = (t) => t.description.startsWith('Notebook parcelado');
    const recent = await callTool('list_transactions', { on_credit_card: true });
    expect(recent.status).toBe(200);
    expect(recent.body.data.transactions.some(isInstallment)).toBe(false);

    const withFuture = await callTool('list_transactions', { on_credit_card: true, include_future: true });
    expect(withFuture.body.data.transactions.filter(isInstallment)).toHaveLength(3);

    const planned = await callTool('list_transactions', { status: 'planned', on_credit_card: true });
    expect(planned.body.data.transactions.filter(isInstallment)).toHaveLength(3);

    const explicitRange = await callTool('list_transactions', {
      from: addMonths(today(), 1), to: addMonths(today(), 3), on_credit_card: true,
    });
    expect(explicitRange.body.data.transactions.filter(isInstallment)).toHaveLength(3);
  });

  it('list_transactions rejeita parâmetros inválidos', async () => {
    const res = await callTool('list_transactions', { type: 'invalido' });
    expect(res.status).toBe(400);
  });

  it('filtros aceitam NOME no lugar do id (como os modelos costumam passar)', async () => {
    const byName = await callTool('list_transactions', { account_id: 'principal' });
    expect(byName.status).toBe(200);
    expect(byName.body.data.transactions.length).toBeGreaterThan(0);

    const byCategory = await callTool('list_transactions', { category_id: 'Mercado' });
    expect(byCategory.status).toBe(200);
    expect(byCategory.body.data.transactions.every((t) => t.category_id === expenseCategoryId)).toBe(true);

    const invoices = await callTool('get_invoices', { card_id: 'nubank' });
    expect(invoices.status).toBe(200);
  });

  it('nome inexistente devolve erro com as opções disponíveis (modelo se corrige)', async () => {
    const res = await callTool('list_transactions', { account_id: 'Conta Fantasma' });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toContain('não encontrada');
    expect(res.body.error.details.disponiveis).toContain('Conta Principal');
  });

  it('referência genérica ("essa conta") resolve sozinha quando há uma única conta', async () => {
    const res = await callTool('list_transactions', { account_id: 'essa conta' });
    expect(res.status).toBe(200);
    expect(res.body.data.transactions.length).toBeGreaterThan(0);
  });

  it('referência genérica com várias contas instrui o modelo a perguntar', async () => {
    await api.post('/api/v1/accounts').set(auth(token))
      .send({ name: 'Poupança', type: 'savings', initial_balance: 0 });

    const res = await callTool('list_transactions', { account_id: 'essa conta' });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toContain('Pergunte ao usuário');
    expect(res.body.error.details.disponiveis).toEqual(
      expect.arrayContaining(['Conta Principal', 'Poupança']),
    );
  });

  it('spending_by_category totaliza por categoria no mês atual', async () => {
    const res = await callTool('spending_by_category', {});
    expect(res.status).toBe(200);
    const row = res.body.data.categories.find((c) => c.category?.id === expenseCategoryId);
    expect(row.total).toBe(300);
    // Total geral inclui também a despesa sem categoria (mercado 300 + conta de luz prevista 250).
    expect(res.body.data.total).toBe(550);
  });

  it('get_budget_status responde has_budget=false sem orçamento cadastrado', async () => {
    const res = await callTool('get_budget_status', { month: '2020-01' });
    expect(res.status).toBe(200);
    expect(res.body.data.has_budget).toBe(false);
  });

  it('get_budget_status calcula previsto x realizado quando há orçamento', async () => {
    const month = today().slice(0, 7);
    const budget = await api.post('/api/v1/budgets').set(auth(token))
      .send({ reference_month: monthStart(today()) });
    budgetId = budget.body.data.id;
    await api.post('/api/v1/budgets/items').set(auth(token)).send({
      budget_id: budgetId, category_id: expenseCategoryId, planned_amount: 400,
    });

    const res = await callTool('get_budget_status', { month });
    expect(res.status).toBe(200);
    expect(res.body.data.has_budget).toBe(true);
    const item = res.body.data.items.find((i) => i.category === 'Mercado');
    expect(item.planned).toBe(400);
    expect(item.realized).toBe(300);
    expect(item.exceeded).toBe(false);
    // Sem ids/ícones no payload: o agente trunca resultados longos e o formato
    // completo cortava categorias do fim do orçamento.
    expect(item.type).toBe('expense');
    expect(item).not.toHaveProperty('item_id');
    expect(res.body.data).not.toHaveProperty('budget');
  });

  it('get_upcoming_bills lista a conta prevista dentro da janela', async () => {
    const res = await callTool('get_upcoming_bills', { days: 10 });
    expect(res.status).toBe(200);
    expect(res.body.data.upcoming.some((t) => t.description === 'Conta de luz')).toBe(true);
  });

  it('get_upcoming_bills inclui lacuna do orçamento que vence hoje', async () => {
    const category = await api.post('/api/v1/categories').set(auth(token))
      .send({ name: 'Saúde', type: 'expense' });
    const subcategory = await api.post('/api/v1/categories/subcategories').set(auth(token))
      .send({ name: 'Unimed', category_id: category.body.data.id });
    await api.post('/api/v1/budgets/items').set(auth(token)).send({
      budget_id: budgetId,
      category_id: category.body.data.id,
      subcategory_id: subcategory.body.data.id,
      planned_amount: 3152.63,
      is_fixed: true,
      due_day: Number(today().slice(-2)),
      account_id: accountId,
    });

    const res = await callTool('get_upcoming_bills', { days: 7, type: 'expense' });
    expect(res.status).toBe(200);
    expect(res.body.data.upcoming).toEqual(expect.arrayContaining([
      expect.objectContaining({
        description: 'Saúde · Unimed',
        amount_planned: 3152.63,
        due_date: today(),
        source: 'budget',
      }),
    ]));
  });

  it('get_upcoming_bills abate lançamento vinculado e mantém só a lacuna do orçamento', async () => {
    const category = await api.post('/api/v1/categories').set(auth(token))
      .send({ name: 'Internet', type: 'expense' });
    await api.post('/api/v1/budgets/items').set(auth(token)).send({
      budget_id: budgetId,
      category_id: category.body.data.id,
      planned_amount: 500,
      is_fixed: true,
      due_day: Number(today().slice(-2)),
      account_id: accountId,
    });
    await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense',
      description: 'Fatura da internet',
      amount_planned: 200,
      competence_date: today(),
      due_date: today(),
      status: 'planned',
      account_id: accountId,
      category_id: category.body.data.id,
    });

    const res = await callTool('get_upcoming_bills', { days: 7, type: 'expense' });
    const internet = res.body.data.upcoming.filter((entry) => entry.category_id === category.body.data.id);
    expect(internet).toEqual(expect.arrayContaining([
      expect.objectContaining({ source: 'transaction', amount_planned: 200 }),
      expect.objectContaining({ source: 'budget', amount_planned: 300 }),
    ]));
    expect(internet.reduce((sum, entry) => sum + Number(entry.amount_planned), 0)).toBe(500);
  });

  it('get_upcoming_bills inclui parcela virtual de dívida sem duplicar orçamento vinculado', async () => {
    const category = await api.post('/api/v1/categories').set(auth(token))
      .send({ name: 'Financiamento', type: 'expense' });
    const item = await api.post('/api/v1/budgets/items').set(auth(token)).send({
      budget_id: budgetId,
      category_id: category.body.data.id,
      planned_amount: 500,
      is_fixed: true,
      due_day: Number(today().slice(-2)),
      account_id: accountId,
    });
    const updatedDebt = await api.put(`/api/v1/debts/${debtId}`).set(auth(token)).send({
      version: debtVersion,
      budget_item_id: item.body.data.id,
      category_id: category.body.data.id,
      account_id: accountId,
    });
    expect(updatedDebt.status).toBe(200);

    const res = await callTool('get_upcoming_bills', { days: 7, type: 'expense' });
    expect(res.status).toBe(200);
    expect(res.body.data.upcoming).toEqual(expect.arrayContaining([
      expect.objectContaining({
        description: 'Financiamento carro · parcela 1/1',
        amount_planned: 500,
        due_date: today(),
        source: 'debt',
      }),
    ]));
    const linkedEntries = res.body.data.upcoming.filter(
      (entry) => entry.category_id === category.body.data.id,
    );
    expect(linkedEntries).toHaveLength(1);
    expect(linkedEntries[0].source).toBe('debt');
  });

  it('get_invoices calcula o total da fatura a partir das transações vinculadas', async () => {
    const invoice = await api.post(`/api/v1/cards/${cardId}/invoices`).set(auth(token)).send({
      reference_month: `${today().slice(0, 7)}-01`,
      closing_date: today(), due_date: addDays(today(), 10),
    });
    await api.post('/api/v1/transactions').set(auth(token)).send({
      type: 'expense', description: 'Compra no cartão', amount_planned: 150,
      competence_date: today(), card_id: cardId, invoice_id: invoice.body.data.id,
    });

    const res = await callTool('get_invoices', { card_id: cardId });
    expect(res.status).toBe(200);
    const inv = res.body.data.invoices.find((i) => i.id === invoice.body.data.id);
    expect(inv.computed_total).toBe(150);
    expect(inv.card.name).toBe('Cartão Nubank');
  });

  it('get_cashflow_projection devolve períodos com saldo acumulado', async () => {
    const res = await callTool('get_cashflow_projection', {});
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.data.periods)).toBe(true);
    expect(typeof res.body.data.opening_balance).toBe('number');
  });

  it('get_goals, get_debts e get_investments devolvem os dados criados', async () => {
    const goals = await callTool('get_goals');
    expect(goals.body.data.goals.some((g) => g.name === 'Viagem' && g.percent === 25)).toBe(true);

    const debts = await callTool('get_debts');
    expect(debts.body.data.total_outstanding).toBe(15000);

    const investments = await callTool('get_investments');
    expect(investments.body.data.total_yield).toBe(50);
  });

  it('get_month_summary calcula receitas, despesas e taxa de poupança', async () => {
    const res = await callTool('get_month_summary', {});
    expect(res.status).toBe(200);
    expect(res.body.data.income_realized).toBe(5000);
    expect(res.body.data.expense_realized).toBe(300);
    expect(res.body.data.result).toBe(4700);
  });

  it('search_categories e search_accounts resolvem nomes citados', async () => {
    await api.post('/api/v1/categories/subcategories').set(auth(token))
      .send({ name: 'Feira', category_id: expenseCategoryId });
    const cats = await callTool('search_categories', { query: 'merc' });
    const found = cats.body.data.categories.find((c) => c.id === expenseCategoryId);
    expect(found).toBeDefined();
    // Sem a lista de subcategorias a Hope nunca chega a preencher subcategory_id.
    expect(found.subcategories).toEqual([expect.objectContaining({ name: 'Feira' })]);

    const accs = await callTool('search_accounts', { query: 'principal' });
    expect(accs.body.data.accounts.some((a) => a.id === accountId)).toBe(true);
  });

  it('escopo por usuário: um segundo usuário não vê os dados do primeiro', async () => {
    const other = await registerUser(api);
    const res = await callToolAs(other.access_token, 'get_balances');
    expect(res.status).toBe(200);
    expect(res.body.data.accounts).toHaveLength(0);
    expect(res.body.data.total_balance).toBe(0);
  });
});
