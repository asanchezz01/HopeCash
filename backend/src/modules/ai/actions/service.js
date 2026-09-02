import crypto from 'node:crypto';
import { db } from '../../../db/knex.js';
import { syncRepo, applyScope } from '../../../core/syncRepo.js';
import { now } from '../../../utils/time.js';
import { badRequest, forbidden, notFound } from '../../../utils/httpError.js';
import { resolveRefId } from '../tools/shared.js';
import { defaultDebitAccount } from '../../../core/transactionDestination.js';

const ACTION_TTL_MS = 15 * 60_000;
const GOAL_NOTE_PREFIX = 'hopecash:goal_movement:';

const round2 = (value) => Math.round(Number(value) * 100) / 100;
const expiresAt = () => new Date(Date.now() + ACTION_TTL_MS).toISOString().slice(0, 23).replace('T', ' ');
const field = (label, value, kind = 'text') => ({ label, value, kind });
// A subcategoria vai junto da categoria no resumo: o card do chat lista os
// campos como vêm daqui, então sem isso ela sumia da proposta.
const categoryLabel = (category, subcategory) => (category
  ? `${category.name}${subcategory ? ` · ${subcategory.name}` : ''}`
  : 'Sem categoria');

const cardDueDate = (purchaseDate, closingDay, dueDay) => {
  const date = new Date(`${purchaseDate}T00:00:00Z`);
  let year = date.getUTCFullYear();
  let month = date.getUTCMonth();
  if (date.getUTCDate() > Number(closingDay)) {
    month += 1;
    if (month > 11) { month = 0; year += 1; }
  }
  if (Number(dueDay) <= Number(closingDay)) {
    month += 1;
    if (month > 11) { month = 0; year += 1; }
  }
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const day = Math.min(Number(dueDay), lastDay);
  return `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
};

function assertWritable(auth, familyId = null) {
  if (auth.readOnly) throw forbidden('Seu acesso a esta conta é somente leitura');
  if (familyId && auth.familyRoles?.[familyId] === 'viewer') {
    throw forbidden('Visualizadores da família não podem propor alterações');
  }
}

async function scopedRecord(auth, entity, ref, displayField, label) {
  const table = entity;
  const query = applyScope(db(table), entity, auth).whereNull(`${table}.deleted_at`);
  let row;
  if (/^[0-9a-f-]{36}$/i.test(ref)) row = await query.clone().where(`${table}.id`, ref).first();
  if (!row) {
    const needle = String(ref).trim().toLowerCase();
    const rows = await query.clone().limit(200);
    row = rows.find((item) => String(item[displayField]).toLowerCase() === needle)
      ?? rows.find((item) => String(item[displayField]).toLowerCase().includes(needle));
  }
  if (!row) throw notFound(`${label} não encontrado`);
  assertWritable(auth, row.family_id);
  return row;
}

async function optionalRef(auth, entity, ref) {
  if (!ref) return null;
  const id = await resolveRefId(auth, entity, ref);
  const row = await syncRepo.findById(entity, auth, id);
  if (row) assertWritable(auth, row.family_id);
  return row;
}

async function optionalScopedRecord(auth, entity, ref, displayField, label) {
  if (!ref) return null;
  return scopedRecord(auth, entity, ref, displayField, label);
}

async function resolveSplits(auth, splits, type, total) {
  const resolved = await Promise.all(splits.map(async (split) => {
    const [category, subcategory] = await Promise.all([
      optionalRef(auth, 'categories', split.category_id),
      optionalScopedRecord(auth, 'subcategories', split.subcategory_id, 'name', 'Subcategoria'),
    ]);
    if (!category || category.type !== type) throw badRequest('A categoria do rateio não corresponde ao tipo do lançamento');
    if (subcategory && subcategory.category_id !== category.id) throw badRequest('A subcategoria não pertence à categoria do rateio');
    return { category_id: category.id, subcategory_id: subcategory?.id ?? null, amount: round2(split.amount) };
  }));
  const cents = resolved.reduce((sum, split) => sum + Math.round(split.amount * 100), 0);
  if (cents !== Math.round(Number(total) * 100)) throw badRequest('As partes do rateio devem somar exatamente o valor do lançamento');
  return resolved;
}

const publicAction = (row) => ({
  id: row.id,
  conversation_id: row.conversation_id,
  message_id: row.message_id,
  tool_name: row.tool_name,
  payload: typeof row.payload === 'string' ? JSON.parse(row.payload) : row.payload,
  summary: typeof row.summary === 'string' ? JSON.parse(row.summary) : row.summary,
  status: row.status,
  result: row.result ? (typeof row.result === 'string' ? JSON.parse(row.result) : row.result) : null,
  error: row.error,
  expires_at: row.expires_at,
  created_at: row.created_at,
});

async function prepareCreateTransaction(auth, params) {
  const [card, category, subcategory] = await Promise.all([
    optionalRef(auth, 'credit_cards', params.card_id),
    optionalRef(auth, 'categories', params.category_id),
    optionalScopedRecord(auth, 'subcategories', params.subcategory_id, 'name', 'Subcategoria'),
  ]);

  // A conta é resolvida à parte porque, ao contrário das outras referências,
  // ela não pode acabar nula: um lançamento sem conta nem cartão não afeta
  // saldo nenhum. `assumedAccount` registra que o destino foi escolhido pelo
  // sistema, para o usuário (ou o host MCP) saber que houve um palpite.
  let account = null;
  let assumedAccount = null;
  if (!card) {
    if (params.account_id) {
      try {
        account = await optionalRef(auth, 'bank_accounts', params.account_id);
      } catch (err) {
        // `resolveRefId` devolve 400 com as opções para o modelo se corrigir.
        // Num host MCP isso vira só uma falha seca, então em vez de recusar
        // caímos na conta padrão e avisamos qual foi usada.
        if (err.status !== 400) throw err;
        assumedAccount = `não encontrei a conta "${params.account_id}"`;
      }
    } else {
      assumedAccount = 'nenhuma conta foi informada';
    }

    if (!account) {
      account = await defaultDebitAccount(auth);
      if (!account) {
        throw badRequest(
          'Não há conta de débito ativa para receber o lançamento. '
          + 'Peça ao usuário para cadastrar uma conta no app antes de lançar.',
        );
      }
      assertWritable(auth, account.family_id);
    } else {
      assumedAccount = null;
    }
  } else if (params.account_id) {
    account = await optionalRef(auth, 'bank_accounts', params.account_id);
  }

  if (account && card) throw badRequest('Informe uma conta ou um cartão, não os dois');
  if (category && category.type !== params.type) throw badRequest('A categoria não corresponde ao tipo do lançamento');
  if (subcategory && (!category || subcategory.category_id !== category.id)) {
    throw badRequest('A subcategoria não pertence à categoria informada');
  }
  const splits = params.category_splits ? await resolveSplits(auth, params.category_splits, params.type, params.amount) : null;
  const paid = card ? false : params.paid;
  const payload = {
    type: params.type,
    description: params.description,
    amount: round2(params.amount),
    date: params.date,
    due_date: params.due_date ?? null,
    paid,
    account_id: account?.id ?? null,
    card_id: card?.id ?? null,
    category_id: category?.id ?? null,
    subcategory_id: subcategory?.id ?? null,
    category_splits: splits,
    notes: params.notes ?? null,
    family_id: params.family_id ?? account?.family_id ?? card?.family_id ?? category?.family_id ?? null,
  };
  assertWritable(auth, payload.family_id);
  return {
    payload,
    // Sobe junto com a proposta para que `confirmAction` possa devolver o
    // aviso ao host MCP, que executa sem passar por um card de confirmação.
    assumedAccount: assumedAccount && account
      ? { name: account.name, reason: assumedAccount }
      : null,
    summary: {
      title: params.type === 'income' ? 'Nova receita' : 'Nova despesa',
      fields: [
        field('Descrição', payload.description), field('Valor', payload.amount, 'money'),
        field('Data', payload.date, 'date'),
        field(
          card ? 'Cartão' : 'Conta',
          card?.name
            ?? (assumedAccount ? `${account.name} (assumida — ${assumedAccount})` : account?.name)
            ?? 'Não informada',
        ),
        field('Categoria', splits ? `${splits.length} categorias (rateio)` : categoryLabel(category, subcategory)),
        field('Situação', paid ? 'Pago' : 'Previsto'),
      ],
    },
  };
}

async function prepareUpdateTransaction(auth, params) {
  const current = await scopedRecord(auth, 'transactions', params.transaction_id, 'description', 'Lançamento');
  const patch = {};
  if (params.description !== undefined) patch.description = params.description;
  if (params.amount !== undefined) patch.amount_value = round2(params.amount);
  if (params.date !== undefined) patch.date = params.date;
  if (params.due_date !== undefined) patch.due_date = params.due_date;
  if (params.notes !== undefined) patch.notes = params.notes;
  if (params.category_id !== undefined) {
    const category = await optionalRef(auth, 'categories', params.category_id);
    if (category && category.type !== current.type) throw badRequest('A categoria não corresponde ao tipo do lançamento');
    patch.category_id = category?.id ?? null;
  }
  if (params.subcategory_id !== undefined) {
    const subcategory = await optionalScopedRecord(auth, 'subcategories', params.subcategory_id, 'name', 'Subcategoria');
    patch.subcategory_id = subcategory?.id ?? null;
    const categoryId = patch.category_id === undefined ? current.category_id : patch.category_id;
    if (subcategory && subcategory.category_id !== categoryId) {
      throw badRequest('A subcategoria não pertence à categoria informada');
    }
  }
  if (params.category_splits !== undefined) {
    const amount = params.amount ?? current.amount_planned ?? current.amount;
    patch.category_splits = params.category_splits == null ? null : await resolveSplits(auth, params.category_splits, current.type, amount);
    if (patch.category_splits) { patch.category_id = null; patch.subcategory_id = null; }
  }
  if (params.account_id !== undefined) {
    patch.account_id = (await optionalRef(auth, 'bank_accounts', params.account_id))?.id ?? null;
    if (patch.account_id) patch.card_id = null;
  }
  if (params.card_id !== undefined) {
    patch.card_id = (await optionalRef(auth, 'credit_cards', params.card_id))?.id ?? null;
    if (patch.card_id) patch.account_id = null;
  }
  if (patch.category_id !== undefined && patch.subcategory_id === undefined && current.subcategory_id) {
    const currentSubcategory = await optionalScopedRecord(auth, 'subcategories', current.subcategory_id, 'name', 'Subcategoria');
    if (currentSubcategory?.category_id !== patch.category_id) patch.subcategory_id = null;
  }
  if (!Object.keys(patch).length) throw badRequest('Nenhuma alteração informada');
  return {
    payload: { transaction_id: current.id, expected_version: current.version, patch },
    summary: {
      title: 'Alterar lançamento',
      fields: [field('Lançamento', current.description), ...Object.entries(patch).map(([key, value]) => field(key, value))],
    },
  };
}

async function preparePayTransaction(auth, params) {
  const current = await scopedRecord(auth, 'transactions', params.transaction_id, 'description', 'Lançamento');
  if (current.status === 'paid') throw badRequest('Esse lançamento já está pago');
  const amount = round2(params.amount ?? current.amount_planned ?? current.amount);
  const interest = round2(params.interest_amount ?? 0);
  if (!(amount > 0) || interest < 0 || interest >= amount) throw badRequest('Valores da baixa inválidos');
  return {
    payload: {
      transaction_id: current.id, expected_version: current.version,
      amount, interest_amount: interest, date: params.date,
    },
    summary: {
      title: 'Dar baixa no lançamento',
      fields: [
        field('Lançamento', current.description), field('Valor pago', amount, 'money'),
        ...(interest ? [field('Juros/multa', interest, 'money')] : []), field('Pagamento', params.date, 'date'),
      ],
    },
  };
}

async function prepareTransfer(auth, params) {
  const fromId = await resolveRefId(auth, 'bank_accounts', params.from_account_id);
  const toId = await resolveRefId(auth, 'bank_accounts', params.to_account_id);
  const [from, to] = await Promise.all([
    syncRepo.findById('bank_accounts', auth, fromId), syncRepo.findById('bank_accounts', auth, toId),
  ]);
  if (!from || !to) throw notFound('Conta não encontrada');
  assertWritable(auth, from.family_id); assertWritable(auth, to.family_id);
  if (from.id === to.id) throw badRequest('As contas devem ser diferentes');
  const payload = {
    from_account_id: from.id, to_account_id: to.id, amount: round2(params.amount),
    date: params.date, description: params.description,
  };
  return {
    payload,
    summary: { title: 'Transferência', fields: [field('De', from.name), field('Para', to.name), field('Valor', payload.amount, 'money'), field('Data', payload.date, 'date')] },
  };
}

async function prepareBudgetItem(auth, params) {
  const [category, subcategory, account, card] = await Promise.all([
    optionalRef(auth, 'categories', params.category_id),
    optionalScopedRecord(auth, 'subcategories', params.subcategory_id, 'name', 'Subcategoria'),
    optionalRef(auth, 'bank_accounts', params.account_id),
    optionalRef(auth, 'credit_cards', params.card_id),
  ]);
  if (!category) throw notFound('Categoria não encontrada');
  if (subcategory && subcategory.category_id !== category.id) {
    throw badRequest('A subcategoria não pertence à categoria informada');
  }
  if (account && card) throw badRequest('Informe conta ou cartão, não os dois');
  const payload = {
    month: params.month, category_id: category.id, subcategory_id: subcategory?.id ?? null,
    planned_amount: round2(params.planned_amount), is_fixed: params.is_fixed,
    due_day: params.due_day ?? null, account_id: account?.id ?? null, card_id: card?.id ?? null,
    family_id: params.family_id ?? account?.family_id ?? card?.family_id ?? category.family_id ?? null,
  };
  assertWritable(auth, payload.family_id);
  return {
    payload,
    summary: { title: 'Item de orçamento', fields: [field('Mês', params.month), field('Categoria', categoryLabel(category, subcategory)), field('Valor previsto', payload.planned_amount, 'money'), ...(payload.due_day ? [field('Dia', payload.due_day)] : [])] },
  };
}

async function prepareGoal(auth, params) {
  const account = await optionalRef(auth, 'bank_accounts', params.linked_account_id);
  const payload = {
    name: params.name, target_amount: round2(params.target_amount), target_date: params.target_date ?? null,
    accumulated_amount: round2(params.accumulated_amount), linked_account_id: account?.id ?? null,
    status: 'active', family_id: params.family_id ?? account?.family_id ?? null,
  };
  assertWritable(auth, payload.family_id);
  return {
    payload,
    summary: { title: 'Nova meta', fields: [field('Meta', payload.name), field('Objetivo', payload.target_amount, 'money'), ...(payload.target_date ? [field('Prazo', payload.target_date, 'date')] : [])] },
  };
}

async function prepareGoalContribution(auth, params) {
  const goal = await scopedRecord(auth, 'goals', params.goal_id, 'name', 'Meta');
  const [account, card] = await Promise.all([
    optionalRef(auth, 'bank_accounts', params.account_id ?? goal.linked_account_id),
    optionalRef(auth, 'credit_cards', params.card_id),
  ]);
  if (!account && !card) throw badRequest('Informe uma conta ou cartão para o aporte');
  const payload = {
    goal_id: goal.id, expected_version: goal.version, amount: round2(params.amount), date: params.date,
    account_id: card ? null : account?.id ?? null, card_id: card?.id ?? null,
  };
  return {
    payload,
    summary: { title: 'Aporte em meta', fields: [field('Meta', goal.name), field('Valor', payload.amount, 'money'), field('Data', payload.date, 'date'), field(card ? 'Cartão' : 'Conta', card?.name ?? account?.name)] },
  };
}

async function prepareCategory(auth, params) {
  assertWritable(auth, params.family_id);
  const payload = { name: params.name, type: params.type, icon: params.icon ?? null, color: params.color ?? null, family_id: params.family_id ?? null };
  return { payload, summary: { title: 'Nova categoria', fields: [field('Nome', payload.name), field('Tipo', payload.type === 'income' ? 'Receita' : 'Despesa')] } };
}

const PREPARERS = {
  create_transaction: prepareCreateTransaction,
  update_transaction: prepareUpdateTransaction,
  pay_transaction: preparePayTransaction,
  create_transfer: prepareTransfer,
  upsert_budget_item: prepareBudgetItem,
  create_goal: prepareGoal,
  add_goal_contribution: prepareGoalContribution,
  create_category: prepareCategory,
};

export async function proposeAction(toolName, auth, params, context = {}) {
  assertWritable(auth);
  if (!context.conversationId) throw badRequest('Ação de escrita exige uma conversa');
  const conversation = await db('ai_conversations')
    .where({ id: context.conversationId, user_id: auth.userId }).first();
  if (!conversation) throw notFound('Conversa não encontrada');
  const prepared = await PREPARERS[toolName](auth, params);
  const ts = now();
  const row = {
    id: crypto.randomUUID(), user_id: auth.userId, actor_id: auth.actorId ?? null,
    conversation_id: conversation.id, message_id: null, tool_name: toolName,
    payload: JSON.stringify(prepared.payload), summary: JSON.stringify(prepared.summary),
    status: 'proposed', result: null, error: null, expires_at: expiresAt(),
    decided_at: null, created_at: ts, updated_at: ts,
  };
  await db('ai_actions').insert(row);
  return {
    proposed: true,
    action: publicAction(row),
    assumed_account: prepared.assumedAccount ?? null,
    message: 'Proposta criada. Aguarde a confirmação do usuário; não diga que a ação já foi executada.',
  };
}

async function ensureInterestCategory(auth, req) {
  const rows = await applyScope(db('categories'), 'categories', auth)
    .whereNull('deleted_at').where('type', 'expense').select('id', 'name');
  const existing = rows.find((row) => row.name.trim().toLowerCase() === 'juros e multas');
  if (existing) return existing.id;
  return (await syncRepo.create('categories', auth, {
    name: 'Juros e Multas', type: 'expense', icon: 'taxes', color: '#C44A4A',
  }, { req })).id;
}

async function executeCreateTransaction(auth, payload, req) {
  const card = payload.card_id ? await syncRepo.findById('credit_cards', auth, payload.card_id) : null;
  const dueDate = payload.due_date ?? (card ? cardDueDate(payload.date, card.closing_day, card.due_day) : payload.paid ? null : payload.date);
  return syncRepo.create('transactions', auth, {
    type: payload.type, description: payload.description, notes: payload.notes,
    amount_planned: payload.amount, amount: payload.paid ? payload.amount : null,
    competence_date: payload.date, due_date: dueDate, payment_date: payload.paid ? payload.date : null,
    status: payload.paid ? 'paid' : 'planned', account_id: payload.account_id,
    card_id: payload.card_id, category_id: payload.category_id,
    subcategory_id: payload.subcategory_id, family_id: payload.family_id,
    category_splits: payload.category_splits,
  }, { req });
}

async function executeUpdateTransaction(auth, payload, req) {
  const current = await syncRepo.findById('transactions', auth, payload.transaction_id);
  if (!current) throw notFound('Lançamento não encontrado');
  assertWritable(auth, current.family_id);
  const patch = { ...payload.patch };
  if ('amount_value' in patch) {
    patch.amount_planned = patch.amount_value;
    if (current.status === 'paid') patch.amount = patch.amount_value;
    delete patch.amount_value;
  }
  if ('date' in patch) {
    patch.competence_date = patch.date;
    if (current.status === 'paid') patch.payment_date = patch.date;
    delete patch.date;
  }
  return syncRepo.update('transactions', auth, current.id, patch, { expectedVersion: payload.expected_version, req });
}

async function executePayTransaction(auth, payload, req) {
  const current = await syncRepo.findById('transactions', auth, payload.transaction_id);
  if (!current) throw notFound('Lançamento não encontrado');
  assertWritable(auth, current.family_id);
  const baseAmount = round2(payload.amount - payload.interest_amount);
  const paid = await syncRepo.update('transactions', auth, current.id, {
    amount: baseAmount, payment_date: payload.date, status: 'paid',
  }, { expectedVersion: payload.expected_version, req });
  let interest = null;
  if (payload.interest_amount > 0) {
    const categoryId = await ensureInterestCategory(auth, req);
    interest = await syncRepo.create('transactions', auth, {
      type: 'expense', description: `Juros/multa ${current.description}`,
      amount: payload.interest_amount, amount_planned: payload.interest_amount,
      competence_date: payload.date, payment_date: payload.date, status: 'paid',
      account_id: current.account_id, category_id: categoryId, family_id: current.family_id,
    }, { req });
  }
  return { transaction: paid, interest_transaction: interest };
}

async function executeTransfer(auth, payload, req) {
  const [from, to] = await Promise.all([
    syncRepo.findById('bank_accounts', auth, payload.from_account_id),
    syncRepo.findById('bank_accounts', auth, payload.to_account_id),
  ]);
  if (!from || !to) throw notFound('Conta não encontrada');
  assertWritable(auth, from.family_id); assertWritable(auth, to.family_id);
  const groupId = crypto.randomUUID();
  const common = { amount: payload.amount, amount_planned: payload.amount, competence_date: payload.date, payment_date: payload.date, status: 'paid', transfer_group_id: groupId };
  const debit = await syncRepo.create('transactions', auth, { ...common, type: 'expense', description: `${payload.description} → ${to.name}`, account_id: from.id, transfer_account_id: to.id, family_id: from.family_id }, { req });
  const credit = await syncRepo.create('transactions', auth, { ...common, type: 'income', description: `${payload.description} ← ${from.name}`, account_id: to.id, transfer_account_id: from.id, family_id: to.family_id }, { req });
  return { transfer_group_id: groupId, debit, credit };
}

async function executeBudgetItem(auth, payload, req) {
  const referenceMonth = `${payload.month}-01`;
  const availableBudgets = await syncRepo.list('budgets', auth, {
    limit: 50,
    filters: { reference_month: referenceMonth },
  });
  let budget = availableBudgets.find(
    (candidate) => (candidate.family_id ?? null) === (payload.family_id ?? null),
  );
  if (!budget) budget = await syncRepo.create('budgets', auth, { reference_month: referenceMonth, scope: payload.family_id ? 'family' : 'personal', family_id: payload.family_id }, { req });
  assertWritable(auth, budget.family_id);
  const items = await syncRepo.list('budget_items', auth, { limit: 200, filters: { budget_id: budget.id } });
  const existing = items.find((item) =>
    item.category_id === payload.category_id
    && (item.subcategory_id ?? null) === payload.subcategory_id
    && (item.account_id ?? null) === payload.account_id
    && (item.card_id ?? null) === payload.card_id);
  const data = { ...payload, budget_id: budget.id };
  delete data.month;
  if (existing) return syncRepo.update('budget_items', auth, existing.id, data, { expectedVersion: existing.version, req });
  return syncRepo.create('budget_items', auth, data, { req });
}

async function executeGoalContribution(auth, payload, req) {
  const goal = await syncRepo.findById('goals', auth, payload.goal_id);
  if (!goal) throw notFound('Meta não encontrada');
  assertWritable(auth, goal.family_id);
  const accumulated = round2(Number(goal.accumulated_amount) + payload.amount);
  const updated = await syncRepo.update('goals', auth, goal.id, {
    accumulated_amount: accumulated,
    status: accumulated >= Number(goal.target_amount) ? 'done' : 'active',
  }, { expectedVersion: payload.expected_version, req });
  const card = payload.card_id ? await syncRepo.findById('credit_cards', auth, payload.card_id) : null;
  const transaction = await syncRepo.create('transactions', auth, {
    type: 'expense', description: `Aporte ${goal.name}`, amount_planned: payload.amount,
    amount: card ? null : payload.amount, competence_date: payload.date,
    due_date: card ? cardDueDate(payload.date, card.closing_day, card.due_day) : null,
    payment_date: card ? null : payload.date, status: card ? 'planned' : 'paid',
    account_id: card ? null : payload.account_id, card_id: card?.id ?? null,
    notes: `${GOAL_NOTE_PREFIX}${JSON.stringify({ goal_id: goal.id, movement_type: 'contribution' })}`,
    family_id: goal.family_id,
  }, { req });
  return { goal: updated, transaction };
}

const EXECUTORS = {
  create_transaction: executeCreateTransaction,
  update_transaction: executeUpdateTransaction,
  pay_transaction: executePayTransaction,
  create_transfer: executeTransfer,
  upsert_budget_item: executeBudgetItem,
  create_goal: (auth, payload, req) => syncRepo.create('goals', auth, payload, { req }),
  add_goal_contribution: executeGoalContribution,
  create_category: (auth, payload, req) => syncRepo.create('categories', auth, payload, { req }),
};

export async function confirmAction(auth, id, req) {
  assertWritable(auth);
  const action = await db('ai_actions').where({ id, user_id: auth.userId }).first();
  if (!action) throw notFound('Ação não encontrada');
  if (action.status !== 'proposed') throw badRequest('Essa ação já foi decidida');
  if (String(action.expires_at) < now()) {
    await db('ai_actions').where({ id }).update({ status: 'expired', updated_at: now() });
    throw badRequest('Essa proposta expirou');
  }
  const claimed = await db('ai_actions').where({ id, status: 'proposed' })
    .update({ status: 'executing', updated_at: now() });
  if (claimed !== 1) throw badRequest('Essa ação já está sendo processada');
  try {
    const payload = JSON.parse(action.payload);
    assertWritable(auth, payload.family_id);
    const result = await EXECUTORS[action.tool_name](auth, payload, req);
    const ts = now();
    await db('ai_actions').where({ id }).update({
      status: 'confirmed', result: JSON.stringify(result), decided_at: ts, updated_at: ts,
    });
    return publicAction(await db('ai_actions').where({ id }).first());
  } catch (err) {
    await db('ai_actions').where({ id }).update({ status: 'failed', error: err.message, decided_at: now(), updated_at: now() });
    throw err;
  }
}

export async function rejectAction(auth, id) {
  const action = await db('ai_actions').where({ id, user_id: auth.userId }).first();
  if (!action) throw notFound('Ação não encontrada');
  if (action.status !== 'proposed') throw badRequest('Essa ação já foi decidida');
  const ts = now();
  await db('ai_actions').where({ id }).update({ status: 'rejected', decided_at: ts, updated_at: ts });
  return publicAction(await db('ai_actions').where({ id }).first());
}

export async function actionsForMessages(auth, conversationId) {
  const rows = await db('ai_actions').where({ user_id: auth.userId, conversation_id: conversationId }).orderBy('created_at');
  return rows.map(publicAction);
}

export { publicAction };
