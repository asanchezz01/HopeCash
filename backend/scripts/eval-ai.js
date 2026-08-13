#!/usr/bin/env node
/**
 * Avaliação de modelos Groq para as tarefas de IA do HopeCash.
 *
 * Roda o golden set de frases pt-BR (extração de lançamentos, com o MESMO
 * prompt da rota /ai/parse-transaction) contra cada modelo candidato e mede
 * acurácia por campo, latência e suporte a tool calling — base objetiva para
 * escolher GROQ_MODEL / GROQ_MODEL_CHAT / GROQ_MODEL_FAST.
 *
 * Uso:
 *   node scripts/eval-ai.js                       # modelos configurados
 *   node scripts/eval-ai.js --models openai/gpt-oss-20b,openai/gpt-oss-120b
 *   node scripts/eval-ai.js --url https://api.groq.com/openai/v1
 */

const args = process.argv.slice(2);
const argValue = (name) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : null;
};
if (argValue('url')) process.env.GROQ_BASE_URL = argValue('url');

// Imports dinâmicos para que --url vença o .env (dotenv não sobrescreve process.env).
const { llm } = await import('../src/modules/ai/llm.js');
const { PARSE_OUTPUT_SCHEMA, parseOutputSchema, parseSystemPrompt, parseUserPayload } =
  await import('../src/modules/ai/prompts/parseTransaction.js');
const { today, addDays } = await import('../src/utils/time.js');

const EVAL_TIMEOUT_MS = 180_000; // modelos grandes + carga do modelo na primeira chamada

// ---------------------------------------------------------------------------
// Contexto fixo (ids estáveis, como os que a rota envia a partir do banco).
// "Nubank" existe como conta E como cartão de propósito — testa desambiguação.
// ---------------------------------------------------------------------------
const context = {
  categories: [
    { id: 'cat-alimentacao', name: 'Alimentação', type: 'expense' },
    { id: 'cat-transporte', name: 'Transporte', type: 'expense' },
    { id: 'cat-moradia', name: 'Moradia', type: 'expense' },
    { id: 'cat-saude', name: 'Saúde', type: 'expense' },
    { id: 'cat-lazer', name: 'Lazer', type: 'expense' },
    { id: 'cat-salario', name: 'Salário', type: 'income' },
    { id: 'cat-outras-receitas', name: 'Outras receitas', type: 'income' },
  ],
  accounts: [
    { id: 'acc-nubank', name: 'Nubank' },
    { id: 'acc-itau', name: 'Itaú' },
    { id: 'acc-carteira', name: 'Carteira' },
  ],
  cards: [
    { id: 'card-nubank', name: 'Cartão Nubank' },
    { id: 'card-visa', name: 'Cartão Visa Itaú' },
  ],
};

const hoje = today();
const ontem = addDays(hoje, -1);
const amanha = addDays(hoje, 1);
const sabadoPassado = (() => {
  const weekday = new Date(`${hoje}T00:00:00Z`).getUTCDay();
  return addDays(hoje, -(((weekday - 6 + 7) % 7) || 7));
})();

/** Golden set: cada caso compara apenas os campos declarados em `expect`. */
const cases = [ 
  {
    transcript: 'gastei 45 reais e cinquenta centavos no mercado ontem',
    expect: { type: 'expense', amount: 45.5, date: ontem, category_id: 'cat-alimentacao', paid: true, installments: 1 },
  },
  {
    transcript: 'paguei 120 de farmácia hoje na conta itaú',
    expect: { type: 'expense', amount: 120, date: hoje, account_id: 'acc-itau', category_id: 'cat-saude' },
  },
  {
    transcript: 'comprei uma televisão de 3200 em 10 vezes no cartão visa',
    expect: { type: 'expense', amount: 3200, card_id: 'card-visa', installments: 10 },
  },
  {
    transcript: 'recebi meu salário de 5800 hoje',
    expect: { type: 'income', amount: 5800, date: hoje, category_id: 'cat-salario' },
  },
  {
    transcript: 'uber para o trabalho 23 e 90',
    expect: { type: 'expense', amount: 23.9, category_id: 'cat-transporte' },
  },
  {
    transcript: 'vou pagar 250 de conta de luz amanhã',
    expect: { type: 'expense', amount: 250, date: amanha, paid: false, category_id: 'cat-moradia' },
  },
  {
    transcript: 'cinquenta reais de pizza no cartão nubank',
    expect: { type: 'expense', amount: 50, card_id: 'card-nubank', account_id: null, category_id: 'cat-alimentacao' },
  },
  {
    transcript: 'caiu um pix de 300 do João na conta nubank',
    expect: { type: 'income', amount: 300, account_id: 'acc-nubank' },
  },
  {
    transcript: 'gastei 80 no cinema sábado passado',
    expect: { type: 'expense', amount: 80, date: sabadoPassado, category_id: 'cat-lazer' },
  },
  {
    transcript: 'quinze e noventa de estacionamento',
    expect: { type: 'expense', amount: 15.9, category_id: 'cat-transporte' },
  },
  {
    transcript: '3 mil reais de aluguel',
    expect: { type: 'expense', amount: 3000, category_id: 'cat-moradia' },
  },
  {
    transcript: 'ganhei 150 de cashback',
    expect: { type: 'income', amount: 150 },
  },
];

// ---------------------------------------------------------------------------

/** Sonda de tool calling: o modelo devolve tool_calls para uma pergunta óbvia? */
async function probeTools(model) {
  try {
    const message = await llm.chat({
      model,
      timeoutMs: EVAL_TIMEOUT_MS,
      temperature: 0,
      tools: [{
        type: 'function',
        function: {
          name: 'get_balance',
          description: 'Consulta o saldo atual de uma conta bancária pelo nome',
          parameters: {
            type: 'object',
            properties: { account: { type: 'string', description: 'Nome da conta' } },
            required: ['account'],
          },
        },
      }],
      messages: [{ role: 'user', content: 'Qual o saldo da minha conta Nubank?' }],
    });
    return message.tool_calls?.length ? 'sim' : 'não chamou';
  } catch (err) {
    return /tool/i.test(err.message ?? '') || /tool/i.test(err.cause?.message ?? '')
      ? 'não suportado' : `erro: ${err.message}`;
  }
}

async function evalModel(model) {
  const results = [];
  for (const c of cases) {
    const started = Date.now();
    let output = null;
    let error = null;
    try {
      const raw = await llm.chatJson({
        model,
        format: PARSE_OUTPUT_SCHEMA,
        temperature: 0,
        timeoutMs: EVAL_TIMEOUT_MS,
        messages: [
          { role: 'system', content: parseSystemPrompt(hoje) },
          { role: 'user', content: parseUserPayload({ transcript: c.transcript, ...context }) },
        ],
      });
      const parsed = parseOutputSchema.safeParse(raw);
      if (parsed.success) {
        output = parsed.data;
        // Espelha a revalidação da rota: ids desconhecidos/"null" viram null.
        const known = {
          category_id: context.categories.filter((c) => c.type === output.type).map((c) => c.id),
          account_id: context.accounts.map((a) => a.id),
          card_id: context.cards.map((c) => c.id),
        };
        for (const [field, ids] of Object.entries(known)) {
          if (output[field] != null && !ids.includes(output[field])) output[field] = null;
        }
      } else {
        error = `schema inválido: ${JSON.stringify(raw).slice(0, 200)}`;
      }
    } catch (err) {
      error = err.message;
    }
    const latencyMs = Date.now() - started;

    const fields = Object.keys(c.expect);
    const wrong = output
      ? fields.filter((f) => {
          const got = output[f] ?? null;
          const want = c.expect[f];
          return typeof want === 'number' ? Math.abs(got - want) > 0.001 : got !== want;
        })
      : fields;
    results.push({ transcript: c.transcript, fields: fields.length, wrong, error, latencyMs, output });
  }
  return results;
}

function report(model, results, toolSupport) {
  const totalFields = results.reduce((sum, r) => sum + r.fields, 0);
  const wrongFields = results.reduce((sum, r) => sum + r.wrong.length, 0);
  const accuracy = ((totalFields - wrongFields) / totalFields) * 100;
  const perfect = results.filter((r) => r.wrong.length === 0 && !r.error).length;
  const avgLatency = results.reduce((sum, r) => sum + r.latencyMs, 0) / results.length;

  console.log(`\n════ ${model} ════`);
  console.log(`Casos perfeitos: ${perfect}/${results.length} · Acurácia por campo: ${accuracy.toFixed(1)}% · Latência média: ${(avgLatency / 1000).toFixed(1)}s · Tool calling: ${toolSupport}`);
  for (const r of results) {
    if (r.error) {
      console.log(`  ✗ "${r.transcript}" → ERRO: ${r.error}`);
    } else if (r.wrong.length) {
      const detail = r.wrong.map((f) => `${f}: esperado ${JSON.stringify(cases.find((c) => c.transcript === r.transcript).expect[f])}, veio ${JSON.stringify(r.output[f] ?? null)}`).join(' · ');
      console.log(`  ✗ "${r.transcript}" → ${detail}`);
    } else {
      console.log(`  ✓ "${r.transcript}" (${(r.latencyMs / 1000).toFixed(1)}s)`);
    }
  }
  return { model, accuracy, perfect, avgLatency, toolSupport };
}

// ---------------------------------------------------------------------------

const health = await llm.health();
if (!health.ok) {
  console.error(`Groq indisponível: ${health.error}`);
  process.exit(1);
}
console.log('Groq disponível');

const models = argValue('models')
  ? argValue('models').split(',').map((m) => m.trim()).filter(Boolean)
  : [...new Set(Object.values(llm.models))];
console.log(`Modelos sob avaliação: ${models.join(', ')} · ${cases.length} casos\n`);

const summaries = [];
for (const model of models) {
  console.log(`Avaliando ${model}…`);
  const toolSupport = await probeTools(model);
  const results = await evalModel(model);
  summaries.push(report(model, results, toolSupport));
}

console.log('\n════ RESUMO ════');
console.log('Modelo'.padEnd(24) + 'Acurácia'.padEnd(12) + 'Perfeitos'.padEnd(12) + 'Latência'.padEnd(12) + 'Tools');
for (const s of summaries.sort((a, b) => b.accuracy - a.accuracy)) {
  console.log(
    s.model.padEnd(24)
    + `${s.accuracy.toFixed(1)}%`.padEnd(12)
    + `${s.perfect}/${cases.length}`.padEnd(12)
    + `${(s.avgLatency / 1000).toFixed(1)}s`.padEnd(12)
    + s.toolSupport,
  );
}
process.exit(0);
