import { badRequest, notFound } from '../../../utils/httpError.js';
import getBalances from './balances.js';
import listTransactions from './transactions.js';
import spendingByCategory from './spending.js';
import getBudgetStatus from './budget.js';
import getUpcomingBills from './bills.js';
import getInvoices from './invoices.js';
import getCashflowProjection from './cashflow.js';
import getGoals from './goals.js';
import getDebts from './debts.js';
import getInvestments from './investments.js';
import getMonthSummary from './summary.js';
import { searchCategories, searchAccounts } from './search.js';
import { WRITE_TOOLS } from './write.js';

/**
 * Registro central de ferramentas financeiras. O mesmo catálogo alimenta o
 * chat (Etapa 2), os insights (Etapa 4) e o servidor MCP (Etapa 6) — cada
 * tool já nasce no formato de function-calling do LLM/MCP (name,
 * description, inputSchema em JSON Schema). Ferramentas de escrita apenas
 * criam propostas; a execução acontece no endpoint explícito de confirmação.
 */
export const TOOLS = [
  getBalances,
  listTransactions,
  spendingByCategory,
  getBudgetStatus,
  getUpcomingBills,
  getInvoices,
  getCashflowProjection,
  getGoals,
  getDebts,
  getInvestments,
  getMonthSummary,
  searchCategories,
  searchAccounts,
  ...WRITE_TOOLS,
];

export const TOOLS_BY_NAME = Object.fromEntries(TOOLS.map((t) => [t.name, t]));

/** Formato de function-calling compatível com Groq/OpenAI/MCP. */
export const toLlmTool = (tool) => ({
  type: 'function',
  function: { name: tool.name, description: tool.description, parameters: tool.inputSchema },
});


/**
 * Executa uma tool pelo nome, validando os parâmetros antes do handler.
 * `auth` sempre vem de `req.auth` — os handlers usam `syncRepo`/`applyScope`,
 * então o escopo por usuário/família é aplicado no mesmo ponto de sempre.
 */
export async function callTool(name, auth, rawParams, context = {}) {
  const tool = TOOLS_BY_NAME[name];
  if (!tool) throw notFound(`Tool desconhecida: ${name}`);
  const parsed = tool.paramsSchema.safeParse(rawParams ?? {});
  if (!parsed.success) throw badRequest('Parâmetros inválidos', parsed.error.flatten());
  return tool.handler(auth, parsed.data, context);
}
