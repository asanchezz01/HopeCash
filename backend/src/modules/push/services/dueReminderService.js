import { db } from '../../../db/knex.js';
import { config } from '../../../config.js';
import { buildDeepLink } from '../deepLinks.js';
import { enqueueForUser } from './deliveryService.js';
import { getAutomationRule } from './automationRulesService.js';

// Limite de transações candidatas examinadas por ciclo do worker — evita que
// uma base muito grande bloqueie o processo por tempo indefinido; as mais
// próximas do vencimento são sempre priorizadas (ORDER BY due_date).
const BATCH_LIMIT = 2000;

const CONTENT_BY_KIND = {
  advance: {
    title: 'Lembrete de vencimento',
    body: 'Você tem uma conta que vence em breve. Toque para conferir os detalhes.',
  },
  due_today: {
    title: 'Conta vence hoje',
    body: 'Uma das suas contas vence hoje. Toque para ver os detalhes.',
  },
  overdue: {
    title: 'Conta em atraso',
    body: 'Identificamos uma conta em atraso. Toque para regularizar.',
  },
};

/** "Hoje" na data civil do fuso do usuário (YYYY-MM-DD), sem depender de bibliotecas externas. */
export function todayInTimezone(timezone) {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  } catch {
    return new Date().toISOString().slice(0, 10);
  }
}

/**
 * Classifica o aviso devido para uma data de vencimento:
 * - `due_today` no dia exato (tem prioridade sobre a antecedência, caso coincidam);
 * - `advance` quando faltam exatamente `advanceDays` dias;
 * - `overdue` apenas 1 dia após o vencimento — política deliberadamente limitada
 *   a um único aviso de atraso, para não repetir diariamente e incomodar o usuário.
 * Retorna `null` quando nenhuma dessas datas é hoje.
 */
export function reminderKindFor(dueDate, today, advanceDays) {
  if (dueDate === today) return 'due_today';
  const due = new Date(`${dueDate}T00:00:00Z`);
  const now = new Date(`${today}T00:00:00Z`);
  const diffDays = Math.round((due - now) / 86_400_000);
  if (advanceDays > 0 && diffDays === advanceDays) return 'advance';
  if (diffDays === -1) return 'overdue';
  return null;
}

async function effectivePreferences(userId, defaultAdvanceDays) {
  const prefs = await db('push_preferences').where({ user_id: userId }).first();
  return {
    pushEnabled: prefs ? !!prefs.push_enabled : true,
    emailEnabled: prefs ? !!prefs.email_notifications_enabled : true,
    dueRemindersEnabled: prefs ? !!prefs.due_reminders_enabled : true,
    advanceDays: prefs ? prefs.reminder_advance_days : defaultAdvanceDays,
    timezone: prefs?.timezone || config.push.defaultTimezone,
  };
}

/**
 * Varre transações de despesa planejadas/em atraso de usuários ativos e
 * enfileira os avisos de vencimento devidos hoje (por usuário, respeitando o
 * fuso e as preferências). Idempotente: a chave de idempotência de cada
 * entrega inclui transação + tipo de aviso + dispositivo, então rodar este
 * processo várias vezes (ou em múltiplas instâncias) nunca duplica envios.
 *
 * Controlado pela regra de automação `due_reminder` (retaguarda): desligada,
 * nenhum aviso sai — mesmo que a preferência do usuário esteja ligada. A
 * antecedência da regra vale como padrão para quem ainda não tem preferência
 * própria salva; quem já tem, mantém sua escolha pessoal.
 */
export async function processDueReminders() {
  const rule = await getAutomationRule('due_reminder');
  if (!rule || !rule.enabled) return { evaluated: 0, enqueued: 0, disabled: true };

  const candidates = await db('transactions')
    .join('users', 'users.id', 'transactions.user_id')
    .where('transactions.type', 'expense')
    .whereIn('transactions.status', ['planned', 'overdue'])
    .whereNotNull('transactions.due_date')
    .whereNull('transactions.deleted_at')
    .whereNull('users.deleted_at')
    .where('users.status', 'active')
    .orderBy('transactions.due_date', 'asc')
    .limit(BATCH_LIMIT)
    .select('transactions.id as transaction_id', 'transactions.user_id', 'transactions.due_date');

  if (!candidates.length) return { evaluated: 0, enqueued: 0 };

  const preferencesCache = new Map();
  let enqueued = 0;

  for (const row of candidates) {
    if (!preferencesCache.has(row.user_id)) {
      preferencesCache.set(row.user_id, await effectivePreferences(row.user_id, rule.frequency_days));
    }
    const prefs = preferencesCache.get(row.user_id);
    if ((!prefs.pushEnabled && !prefs.emailEnabled) || !prefs.dueRemindersEnabled) continue;

    const today = todayInTimezone(prefs.timezone);
    const kind = reminderKindFor(row.due_date, today, prefs.advanceDays);
    if (!kind) continue;

    const result = await enqueueForUser({
      sourceType: 'due_reminder',
      sourceId: row.transaction_id,
      reminderKind: kind,
      userId: row.user_id,
      idempotencyPrefix: `due_reminder:${row.transaction_id}:${kind}`,
      sendPush: prefs.pushEnabled,
      includeEmail: prefs.emailEnabled,
    });
    enqueued += result.created;
  }

  return { evaluated: candidates.length, enqueued };
}

const formatMoneyBR = (value) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(Number(value ?? 0));

const formatDateBR = (isoDate) => {
  const [y, m, d] = String(isoDate ?? '').slice(0, 10).split('-');
  return d && m && y ? `${d}/${m}/${y}` : String(isoDate ?? '');
};

/** Corpo detalhado usado no e-mail: identifica a conta, o valor e o vencimento. */
export function detailedReminderBody(kind, transaction) {
  const name = transaction.description || 'Conta';
  const amount = formatMoneyBR(transaction.amount_planned ?? transaction.amount);
  const due = formatDateBR(transaction.due_date);
  if (kind === 'overdue') {
    return `A conta "${name}" no valor de ${amount} venceu em ${due} e está em atraso. Acesse o app para regularizar.`;
  }
  if (kind === 'due_today') {
    return `A conta "${name}" no valor de ${amount} vence hoje (${due}).`;
  }
  return `A conta "${name}" no valor de ${amount} vence em ${due}.`;
}

/**
 * Conteúdo de um aviso de vencimento. O push é genérico (sem valores nem
 * descrições, pois aparece na tela de bloqueio); o e-mail — canal privado —
 * detalha qual conta, o valor e a data de vencimento.
 */
export async function dueReminderContent(delivery) {
  const content = CONTENT_BY_KIND[delivery.reminder_kind] ?? CONTENT_BY_KIND.due_today;
  const transaction = await db('transactions').where({ id: delivery.source_id }).first();
  const deepLink = transaction ? buildDeepLink('/transactions', { openTransactionId: transaction.id }) : '/transactions';
  const body = delivery.channel === 'email' && transaction
    ? detailedReminderBody(delivery.reminder_kind, transaction)
    : content.body;
  return {
    title: content.title,
    body,
    deepLink,
    data: { type: 'due_reminder', reminder_kind: delivery.reminder_kind ?? '', transaction_id: delivery.source_id ?? '' },
  };
}
