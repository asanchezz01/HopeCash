/**
 * Um lançamento **pago** precisa de destino: uma conta OU um cartão.
 *
 * Sem nenhum dos dois ele aparece no extrato mas não move saldo algum — vira
 * um registro órfão que o usuário só descobre ao conferir a conta. Levantamento
 * de 2026-08-08 achou 4 assim em produção, incluindo um salário de R$ 1.570.
 *
 * Por que só o **pago**: um lançamento `planned` é previsão. Ainda não moveu
 * dinheiro, e é legítimo o usuário anotar uma conta a vencer antes de decidir
 * de onde vai pagar — a conta entra na baixa. Todos os 4 órfãos reais eram
 * `paid`; nenhum `planned` sem destino existia em produção.
 *
 * A regra vive aqui, e não no schema Zod da entidade, porque precisa valer nos
 * DOIS caminhos de escrita, que não compartilham validação:
 *   - REST (`crudRouter` → `syncRepo`), onde o PUT é um patch parcial;
 *   - `POST /sync/push`, que aceita `payload: z.record(z.any())` e grava
 *     direto na tabela, sem passar pelo schema da entidade.
 *
 * ÚNICA exceção: a baixa de variação de orçamento. Fecha a diferença entre
 * previsto e realizado sem movimentar dinheiro, então nasce de propósito sem
 * conta e sem cartão (ver `finance_repository.dart`, que grava
 * `accountId: const Value(null)` junto com esta nota estruturada).
 */
import { db } from '../db/knex.js';
import { applyScope } from './syncRepo.js';

const BUDGET_VARIANCE_PREFIX = 'hopecash:budget_variance:';

export const isBudgetVariance = (notes) =>
  typeof notes === 'string' && notes.startsWith(BUDGET_VARIANCE_PREFIX);

export const DESTINATION_REQUIRED = 'Informe a conta ou o cartão do lançamento pago — '
  + 'sem um dos dois ele não movimenta saldo nenhum.';

/**
 * @param {object} next estado final da linha (para update, já mesclado com o
 *   registro atual — um patch que só muda a descrição não pode ser recusado
 *   por não repetir a conta).
 * @returns {boolean} true se falta destino e ele é obrigatório.
 */
export function needsDestination(next) {
  if (!next) return false;
  if (next.account_id || next.card_id) return false;
  if (next.status !== 'paid') return false;
  return !isBudgetVariance(next.notes);
}

/** Mescla o patch sobre o registro atual respeitando nulos explícitos. */
export const mergeForDestinationCheck = (current, patch) => ({
  ...(current ?? {}),
  ...(patch ?? {}),
});

/**
 * Ordem de preferência para "conta de débito": aquela de onde o dinheiro
 * realmente sai no dia a dia. `investment` fica de fora — lançar uma despesa
 * corriqueira numa conta de investimento distorce saldo e projeção de caixa.
 */
const DEBIT_ACCOUNT_TYPES = ['checking', 'digital', 'wallet', 'cash', 'savings'];

/** Destino usado quando o lançamento chega sem conta identificável. */
export async function defaultDebitAccount(auth) {
  const rows = await applyScope(db('bank_accounts'), 'bank_accounts', auth)
    .whereNull('bank_accounts.deleted_at')
    .where('bank_accounts.is_active', true)
    .select('id', 'name', 'type', 'family_id', 'created_at');

  const usable = rows.filter((row) => DEBIT_ACCOUNT_TYPES.includes(row.type));
  if (usable.length === 0) return null;

  usable.sort((a, b) => {
    const byType = DEBIT_ACCOUNT_TYPES.indexOf(a.type) - DEBIT_ACCOUNT_TYPES.indexOf(b.type);
    if (byType !== 0) return byType;
    // Empate no tipo: a mais antiga é a "principal" na prática.
    return String(a.created_at).localeCompare(String(b.created_at));
  });
  return usable[0];
}
