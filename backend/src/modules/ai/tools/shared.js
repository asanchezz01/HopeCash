import { z } from 'zod';
import { db } from '../../../db/knex.js';
import { applyScope } from '../../../core/syncRepo.js';
import { badRequest } from '../../../utils/httpError.js';

export const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Data no formato YYYY-MM-DD');
export const uuid = z.string().uuid();

/** Referência a conta/cartão/categoria: aceita o id OU o nome citado na frase. */
export const idOrName = z.string().trim().min(1).max(120);

export const round2 = (n) => Math.round(n * 100) / 100;

/** Quantidade de dias entre duas datas ISO, inclusive. */
export const daysBetween = (from, to) =>
  Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000) + 1;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const REF_LABELS = {
  bank_accounts: 'Conta',
  credit_cards: 'Cartão',
  categories: 'Categoria',
};

/** Referências genéricas que os modelos passam ao resolver "nessa conta" etc. */
const GENERIC_REFS = {
  bank_accounts: /^((ess|dess|nest)[ae]s?|minh[ao]s?|[ao]s?)?\s*contas?$/i,
  credit_cards: /^((ess|dess|nest)[ae]s?|meus?|[ao]s?)?\s*cart([ãa]o|[õo]es)$/i,
  categories: /^((ess|dess|nest)[ae]s?|minh[ao]s?|[ao]s?)?\s*categorias?$/i,
};

/**
 * Modelos costumam passar o NOME ("Nubank", "Débito") onde a tool espera id.
 * Resolve id-ou-nome para o id real, dentro do escopo do usuário:
 * 1. igualdade (case-insensitive) vence;
 * 2. referência genérica ("essa conta") com uma única opção resolve sozinha —
 *    com várias, o erro instrui o modelo a perguntar ao usuário;
 * 3. senão, primeira correspondência parcial;
 * 4. não achou → 400 com as opções — o agente devolve ao modelo, que se corrige.
 */
export async function resolveRefId(auth, entity, ref) {
  if (ref == null || UUID_RE.test(ref)) return ref;
  const label = REF_LABELS[entity];
  const rows = await applyScope(db(entity), entity, auth)
    .whereNull('deleted_at').limit(200).select('id', 'name');
  const names = rows.map((r) => r.name);
  const needle = ref.trim().toLowerCase();

  const exact = rows.find((r) => r.name.toLowerCase() === needle);
  if (exact) return exact.id;

  if (GENERIC_REFS[entity].test(needle)) {
    if (rows.length === 1) return rows[0].id;
    throw badRequest(
      `Referência genérica "${ref}" é ambígua. Pergunte ao usuário a qual se refere: ${names.join(', ')}.`,
      { disponiveis: names },
    );
  }

  const partial = rows.find((r) => r.name.toLowerCase().includes(needle));
  if (partial) return partial.id;

  throw badRequest(
    `${label} "${ref}" não encontrada. Opções do usuário: ${names.join(', ')}. Se o contexto da conversa indicar qual é, chame a ferramenta de novo com esse nome; senão, pergunte ao usuário.`,
    { disponiveis: names },
  );
}
