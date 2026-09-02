import { z } from 'zod';
import { addDays, today } from '../../../utils/time.js';

/**
 * Prompt e contratos da extração de lançamentos por voz/texto.
 * Compartilhado entre a rota /ai/parse-transaction e o script de avaliação
 * de modelos (scripts/eval-ai.js) — mudou aqui, mudou nos dois.
 */

/** Schema JSON imposto ao Groq via structured outputs (`response_format`). */
export const PARSE_OUTPUT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    type: { type: 'string', enum: ['expense', 'income'] },
    amount: { type: 'number' },
    description: { type: 'string' },
    date: { type: 'string' },
    category_id: { type: ['string', 'null'] },
    subcategory_id: { type: ['string', 'null'] },
    account_id: { type: ['string', 'null'] },
    card_id: { type: ['string', 'null'] },
    installments: { type: 'integer' },
    paid: { type: 'boolean' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
  },
  required: [
    'type', 'amount', 'description', 'date', 'category_id', 'subcategory_id',
    'account_id', 'card_id', 'installments', 'paid', 'confidence',
  ],
};

/** Validação defensiva da resposta do modelo antes de devolver ao app. */
export const parseOutputSchema = z.object({
  type: z.enum(['expense', 'income']),
  amount: z.coerce.number().positive().max(1_000_000_000),
  description: z.string().max(200),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).catch(() => today()),
  category_id: z.string().nullish(),
  subcategory_id: z.string().nullish(),
  account_id: z.string().nullish(),
  card_id: z.string().nullish(),
  installments: z.coerce.number().int().min(1).max(24).catch(1),
  paid: z.coerce.boolean().catch(true),
  confidence: z.enum(['high', 'medium', 'low']).catch('low'),
});

const WEEKDAYS_PT = ['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'];

export const parseSystemPrompt = (date) => `Você extrai lançamentos financeiros de frases faladas em português brasileiro.
Hoje é ${WEEKDAYS_PT[new Date(`${date}T00:00:00Z`).getUTCDay()]}, ${date}. Datas no formato YYYY-MM-DD; sem menção de data, use hoje.
Datas relativas: ontem = ${addDays(date, -1)}, anteontem = ${addDays(date, -2)}, amanhã = ${addDays(date, 1)}; "sexta passada" e afins = o dia da semana citado na semana anterior.
Valores por extenso ("quarenta e cinco reais") viram número (45.00). Em valores monetários falados, "23 e 90" significa 23.90 e "quinze e noventa" significa 15.90; nunca some as duas partes. "Em 3 vezes" ou "3x" significa installments: 3 (senão 1).
"recebi", "caiu", "entrou", "ganhei" indicam type "income"; o padrão é "expense".
"vou pagar", "ainda não paguei", data futura indicam paid: false; o padrão é true.
Escolha category_id, account_id e card_id SOMENTE dentre os ids fornecidos. Para a categoria, combine também pelo significado da despesa, mesmo que o nome da categoria não seja falado: Uber e estacionamento são Transporte; mercado e pizza são Alimentação; farmácia é Saúde; aluguel e conta de luz são Moradia; cinema é Lazer. Se nada encaixar bem, use null. Nunca invente ids.
subcategory_id só pode ser uma das subcategorias listadas para a categoria escolhida; se a lista vier vazia ou nenhuma encaixar, use null.
Cartão de crédito só se aplica a despesas; preencha card_id OU account_id, não ambos.
description é um resumo curto do que foi comprado/recebido (ex.: "Mercado", "Uber para o aeroporto"), sem o valor.
confidence reflete sua certeza geral na extração.
Responda apenas com o JSON.`;

/** Monta o payload de usuário com a frase e o contexto de ids reais. */
export const parseUserPayload = ({ transcript, categories, subcategories = [], accounts, cards }) => JSON.stringify({
  frase: transcript,
  categorias: categories.map((c) => ({ id: c.id, nome: c.name, tipo: c.type })),
  subcategorias: subcategories.map((s) => ({ id: s.id, nome: s.name, categoria_id: s.category_id })),
  contas: accounts.map((a) => ({ id: a.id, nome: a.name })),
  cartoes: cards.map((c) => ({ id: c.id, nome: c.name })),
});
