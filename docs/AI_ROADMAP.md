# HopeCash — IA & MCP: Plano de Implementação

> Roadmap para transformar o HopeCash em um app com assistente financeiro inteligente, usando o
> Groq com fallback para Cerebras (LLM) e Azure Speech (voz), com uma arquitetura de ferramentas compatível com MCP.
> Cada etapa é deployável sozinha e entrega valor incremental.

## 1. Visão

Um assistente financeiro ("**Hope**") embutido no app que:

- **Conversa** sobre as finanças do usuário em pt-BR ("quanto gastei com mercado este mês?").
- **Executa tarefas** — lançamentos, baixas, transferências, orçamento — sempre com confirmação.
- **Gera insights proativos** — resumo mensal, gastos fora do padrão, orçamento estourando, contas a vencer.
- **Automatiza classificação** — categorização de importações, notificações bancárias sem regra.

**Premissa de privacidade atual**: somente os fatos necessários à resposta são enviados à Cerebras ou ao Groq;
o texto sintetizado é enviado ao Azure Speech. Escritas continuam locais, auditadas e dependem de
confirmação humana. IA é opt-out por usuário (Configurações).

## 2. Ponto de partida (o que já existe)

| Peça | Estado |
|---|---|
| Cliente LLM | `modules/ai/llm.js` — Groq → Cerebras: chat, chatJson, chatStream, tools, health; retry, rate-limit e fallback |
| `POST /ai/parse-transaction` | Voz → lançamento estruturado com ids reais do usuário; nunca grava; fallback local no app |
| `GET /ai/health` | Estado dos provedores LLM (app e retaguarda), com card de alerta no dashboard da retaguarda |
| Toolbox somente-leitura | `modules/ai/tools/` — 13 tools (saldos, lançamentos, orçamento, fluxo de caixa, faturas, metas, dívidas, investimentos, resumo do mês, busca); `GET/POST /ai/tools*` para debug (não-prod) |
| Config | `CEREBRAS_API_KEY`, `GROQ_API_KEY` e modelos por provedor; Azure Speech para TTS |
| Camada de dados segura | `syncRepo` — escopo user/family forçado + auditoria em toda escrita |
| App | `AiApi` (Dio), `voice_add_sheet` com confirmação via formulário pré-preenchido |
| Dados prontos p/ IA | `import_items.suggested_category_id`, `notifications` (tipos `unusual_expense`, `budget_exceeded`…), `ocr_data` em anexos |

### Migração dos provedores (2026-08-13)

- Ollama foi substituído pela API Groq compatível com OpenAI. O chat principal usa
  `openai/gpt-oss-120b`; extração estruturada usa `openai/gpt-oss-20b`.
- Kokoro/Coqui e o pós-processamento local foram substituídos por Azure Speech REST
  com SSML e a voz `pt-BR-ThalitaMultilingualNeural`.
- O cliente normaliza argumentos de tool calls para objetos internos, preserva SSE,
  structured outputs, retry e as barreiras de confirmação/evidência existentes.
- `AI_ENABLED=false` continua sendo o bloqueio global; e-mail, push e scheduler têm
  chaves independentes e não são habilitados junto com a Hope.

### Fallback Groq → Cerebras (2026-08-14)

- O cliente usa `openai/gpt-oss-120b` no Groq como primeira opção e preserva o
  `gpt-oss-120b` da Cerebras como fallback de mesma família/qualidade.
- Rate limits respeitam `Retry-After`; após uma nova falha, quota, timeout ou
  indisponibilidade, a requisição é refeita na Cerebras.
- `LLM_MAX_COMPLETION_TOKENS` limita a reserva de saída (padrão: 1200), reduzindo
  pressão de TPM sem cortar o contexto enviado ao modelo.

## 3. Arquitetura alvo

```
 App Flutter                Retaguarda            Hosts MCP externos
 (chat, voz, insights)      (telemetria IA)       (Claude Desktop, IDEs…)
      │ REST + SSE               │                     │ MCP Streamable HTTP + token pessoal
      ▼                          ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                Backend Express — modules/ai                     │
│                                                                 │
│  llm.js       cliente Groq: chat, tools, structured outputs,    │
│               streaming, health, retry, modelo por tarefa       │
│  tools/       REGISTRO DE FERRAMENTAS (núcleo da arquitetura):  │
│               nome + descrição + JSON Schema + handler +        │
│               flag read|write — formato compatível com MCP      │
│  agent.js     loop de tool calling (limite de iterações/tempo)  │
│  insights/    fatos determinísticos (SQL) + narração (LLM)      │
│  actions      propor → confirmar → executar (duas fases)        │
│  mcp.js       adaptador MCP sobre o MESMO registro (Etapa 6)    │
└──────────────┬────────────────────────────┬─────────────────────┘
               │ syncRepo (escopo + audit)  │ HTTP
               ▼                            ▼
              MySQL                 Groq + Azure Speech
```

### Princípios de projeto

1. **Números são determinísticos**: agregações vêm de SQL; o LLM só interpreta e narra. Nunca pedir
   ao modelo para somar linhas cruas.
2. **Escrita em duas fases**: a IA propõe, o usuário confirma, o servidor executa via `syncRepo`
   (auditado). A IA **nunca** grava direto — mesmo padrão do parse por voz atual.
3. **Um único catálogo de ferramentas**: chat interno, voz, insights e o servidor MCP externo
   consomem o mesmo registro. Schema JSON por tool desde o dia 1 = adaptador MCP vira trivial.
4. **Escopo inegociável**: toda tool executa com `req.auth` via `syncRepo`; ids retornados pelo
   modelo são revalidados contra o banco (padrão já usado no parse-transaction).
5. **Degradação graciosa**: provedor fora do ar → app 100% funcional, recursos de IA se ocultam ou
   caem em fallback (padrão já existente na voz).
6. **Prompt injection**: descrições de transações e textos do usuário entram no prompt como *dados*;
   não existe tool "executar SQL"; escrita sempre passa por confirmação humana.

### Interação com o sync (local-first)

Escritas confirmadas acontecem no **servidor** (`syncRepo.create/update` → `version++`,
`updated_at`) e chegam ao app pelo `pull` incremental normal. O app dispara um sync imediatamente
após cada ação confirmada no chat, para o usuário ver o efeito na hora.

## 4. Etapas

### Etapa 0 — Fundação: cliente Ollama e infraestrutura do módulo `ai` (P)

Refatorar o módulo para suportar tudo que vem depois, sem mudança visível ao usuário.

- `modules/ai/ollama.js`: cliente único — `chat()`, `chatStream()`, `chatWithTools()`,
  `embed()`, `health()`; retry com backoff, timeouts, erros tipados.
- Modelo por tarefa: `OLLAMA_MODEL` (default), `OLLAMA_MODEL_CHAT`, `OLLAMA_MODEL_FAST`
  (parsing/categorização) — tudo com fallback para o default. Atualizar `.env.example`.
- `GET /ai/health` (autenticado): status do Ollama + modelos carregados; exibir na retaguarda.
- Migrar `/ai/parse-transaction` para o cliente novo (comportamento idêntico, testes existentes passam).
- Script de avaliação de modelos (`backend/scripts/eval-ai.js`): golden set de frases pt-BR →
  compara llama3.1 vs qwen3 etc. em qualidade de tool calling/extração, para escolher o modelo
  de cada tarefa com dados, não achismo.
- Testes com Ollama mockado (vitest + fetch mock).

**Pronto quando**: parse por voz funciona igual, `/ai/health` responde, avaliação executada e
modelos escolhidos documentados neste arquivo.

#### Resultado da Etapa 0 (2026-07-15)

Entregue: `modules/ai/ollama.js` (chat, chatJson, chatStream, embed, health; retry só em falha
transiente — timeout não re-tenta), prompts em `modules/ai/prompts/`, `GET /ai/health` (app) e
`GET /retaguarda/ai/health` + card "Servidor de IA" no dashboard da retaguarda (alerta quando um
modelo configurado não está instalado), `npm run eval:ai`, 65 testes verdes.

**Avaliação de modelos** (golden set, 12 frases pt-BR) — achados em ambiente privado de IA, inicialmente com Ollama 0.30.7:

| Modelo | Resultado |
|---|---|
| `llama3.1` (era o padrão configurado) | **Não estava instalado no servidor** — parse por voz estava quebrado em produção |
| `phi4:14b` | **Quebrado**: `llama-server … core dumped` em toda chamada; sem suporte a tool calling. Removido do servidor |
| `gemma4:26b` | Instável entre execuções (55–89% de acurácia, latência 8–20s): o template vaza tokens (`<|tool_response>`, `<channel|>`, anos trocados como `2426`/`2024`) mesmo após atualizar o Ollama para 0.32.0 — defeito do próprio arquivo do modelo (conversão/quantização), não do runtime |
| `qwen3:8b` | **100% de acurácia, 12/12 casos perfeitos, ~6s de latência média, tool calling ok.** Instalado no servidor e adotado como padrão |
| `qwen3.5:35b` | **100% de acurácia, 12/12 casos perfeitos, ~1,1s de latência média com `think:false`, tool calling e visão.** Adotado como modelo único em 2026-07-17, com contexto 64K e 100% nas duas GPUs |
| `minicpm-v` / `nomic-embed-text` | Visão e embeddings — úteis nas Etapas 5/7 |

**Manutenção realizada no servidor Ollama** (2026-07-15, via SSH):
1. Ollama atualizado 0.30.7 → 0.32.0 (`install.sh` oficial).
2. A atualização resetou o serviço systemd para bind em `127.0.0.1`, derrubando o acesso externo
   que o backend depende — corrigido com um drop-in `/etc/systemd/system/ollama.service.d/hostbind.conf`
   (`OLLAMA_HOST=0.0.0.0`), separado do `multigpu.conf` existente, resistente a próximas atualizações.
3. `phi4:14b` removido (core dump).
4. `qwen3:8b` instalado e definido como `OLLAMA_MODEL` padrão em `.env`/`.env.example`/`config.js`
   (chat, fast e default todos usam `qwen3:8b` por ora — reavaliar por tarefa quando o chat da
   Etapa 2 existir, com um modelo maior possivelmente melhor para conversas longas).

#### Migração para modelo único (2026-07-17)

- `qwen3.5:35b` instalado como único modelo Ollama disponível; `qwen3:8b`, `gemma4:26b`,
  `minicpm-v` e `nomic-embed-text` foram removidos após a validação.
- Contexto padrão de 65.536 tokens, KV cache `q8_0`, Flash Attention, paralelismo 1 e distribuição
  forçada nas duas GPUs. O runner ocupa cerca de 24 GB e permanece 100% em GPU.
- Coaguru passou a usar o mesmo modelo e manteve o BGE-M3 em CPU. O Open WebUI foi recriado com a
  imagem CPU, sem acesso CUDA, e lista somente `qwen3.5:35b`.
- Structured outputs usam `think:false` por padrão; o golden set da Hope terminou em 12/12 casos,
  100% por campo, ~1,1 s de latência média e tool calling funcional.

Decisões de prompt mantidas: `chatJson` extrai o primeiro JSON válido do texto (defesa contra
vazamento de tokens em modelos problemáticos); datas relativas pré-calculadas no prompt
(ontem/anteontem/amanhã) — tabela completa de 7 dias piorou o resultado no gemma4 (prompt enxuto
vence); sem uso prático agora que o modelo padrão (`qwen3:8b`) resolve datas relativas sozinho
com 100% de acerto no golden set.

Pendências futuras: reavaliar `qwen3:8b` vs. um modelo maior (ex. `qwen3:14b`, se instalado) para
`OLLAMA_MODEL_CHAT` quando a Etapa 2 (chat) chegar — conversas abertas exigem mais raciocínio que
extração estruturada. `gemma4:26b` e `phi4` seguem no roadmap apenas como registro do que não funcionou.

### Etapa 1 — Toolbox financeira somente-leitura (M)

O catálogo de ferramentas que alimenta chat, insights e MCP. Cada tool é um wrapper fino sobre
lógica já existente (dashboard, cashflow, budgets), com JSON Schema estilo MCP e handler que recebe
`(auth, params)`.

| Tool | Responde |
|---|---|
| `get_balances` | Saldo por conta + total |
| `list_transactions` | Filtros: período, tipo, categoria, conta, cartão, texto, status |
| `spending_by_category` | Gasto por categoria/subcategoria num período, com comparativo |
| `get_budget_status` | Orçado × realizado do mês, por categoria |
| `get_upcoming_bills` | Contas a pagar/receber nos próximos N dias (inclui parcelas e recorrências) |
| `get_invoices` | Faturas de cartão (aberta/fechada, valor, vencimento, melhor dia) |
| `get_cashflow_projection` | Projeção de fluxo de caixa |
| `get_goals` / `get_debts` / `get_investments` | Status de metas, dívidas, investimentos |
| `get_month_summary` | Receitas, despesas, resultado, taxa de poupança do mês |
| `search_categories` / `search_accounts` | Resolução de nomes citados → ids |

- Registro central: `modules/ai/tools/index.js` exporta `{ name, description, inputSchema, scope: 'read'|'write', handler }`.
- Testes unitários por tool (SQLite, determinístico).

**Pronto quando**: todas as tools testadas e um endpoint interno de debug (`POST /ai/tools/:name` em dev) permite exercitá-las.

#### Resultado da Etapa 1 (2026-07-15)

Entregue: as 13 tools da tabela acima em `modules/ai/tools/*.js`, cada uma como
`{ name, description, scope: 'read', inputSchema (JSON Schema), paramsSchema (zod), handler(auth, params) }`;
registro central `modules/ai/tools/index.js` (`TOOLS`, `TOOLS_BY_NAME`, `callTool()`, `toOllamaTool()` já no
formato de function-calling do Ollama/MCP); `GET /ai/tools` e `POST /ai/tools/:name` em `ai.routes.js`,
montados apenas fora de produção (`!config.isProd`); 15 testes novos cobrindo cada tool, validação de
parâmetros, tool desconhecida (404) e isolamento por usuário — **80 testes verdes** no total.

Para evitar duplicar lógica complexa já existente, `get_budget_status` e `get_cashflow_projection` reusam
serviços extraídos das rotas originais: `modules/budgets/budgets.service.js` (`getBudgetSummary`,
`findBudgetForMonth`) e `modules/cashflow/cashflow.service.js` (`getCashflowProjection`) — as rotas
`GET /budgets/:id/summary` e `GET /cashflow` viraram wrappers finos sobre os mesmos serviços, comportamento
idêntico, sem duplicação entre tool e rota REST. As demais tools (saldos, lançamentos, gasto por categoria,
contas a vencer, faturas, metas, dívidas, investimentos, resumo do mês, busca de categoria/conta) têm
consultas próprias e enxutas — não valia a pena extrair um serviço para lógicas de poucas linhas.

### Etapa 2 — Chat "Hope": agente conversacional somente-leitura (M/G)

Lançamento seguro do assistente: responde qualquer pergunta sobre as finanças, ainda sem escrever.

**Backend**
- `POST /ai/chat` com resposta em **SSE** (streaming de texto + eventos de tool call).
- Loop de agente: Ollama tool calling sobre o registro da Etapa 1; máx. ~6 iterações, timeout global,
  truncamento de resultados grandes (o modelo recebe agregados, não dumps).
- Persistência: tabelas `ai_conversations` (id, user_id, title, timestamps) e `ai_messages`
  (role, content, tool_calls JSON, tool_results JSON). REST simples — chat não entra no sync
  (só funciona online, pois depende do Ollama).
- Persona pt-BR: objetiva, cita números formatados em R$, sugere follow-ups, nunca inventa dados
  (se a tool não retornou, diz que não encontrou). Prompts versionados em `modules/ai/prompts/`.
- Rate limit dedicado (ex.: 30 msg/15min) — proteger o servidor Ollama.

**App**
- Tela de chat (rota no shell + atalho no dashboard): histórico, streaming, markdown,
  chips de sugestão ("Como está meu orçamento?", "O que vence esta semana?"), entrada por voz
  reutilizando o speech-to-text existente.
- Feature flag: some da UI se `/ai/health` indisponível.

**Pronto quando**: perguntas de leitura respondem com números corretos (validados contra as telas) e streaming flui no app.

#### Resultado da Etapa 2 (2026-07-15)

**Backend**
- `modules/ai/agent.js` — loop do agente: máx. 6 iterações (a última roda sem tools, forçando resposta em
  texto), deadline global de 120s, resultados de tool truncados em 6.000 chars, erro de tool vira dado
  para o modelo se corrigir. `think: false` (qwen3 é modelo "thinking"; desligar corta latência) com
  fallback automático para modelos sem suporte ao parâmetro.
- `POST /ai/chat` em `modules/ai/chat.routes.js` — SSE com eventos `meta` (conversation_id), `tool`
  (nome da consulta), `delta` (texto), `done`, `error`; erros pós-início do stream nunca viram 5xx.
  Rate limit dedicado: 30 msg/15min.
- Migration `ai_conversations` + `ai_messages` (fora do registro de sync — chat só existe online);
  histórico de até 20 mensagens por rodada; `tool_calls` da resposta salvos para auditoria.
  `GET/DELETE /ai/conversations*` — exclusão definitiva (LGPD).
- 7 testes novos com streaming NDJSON mockado (**87 verdes** no total).
- Smoke test contra o Ollama real: tool call chega via streaming, `think:false` aceito pelo qwen3,
  resposta final correta e formatada em R$.

**App**
- `AiApi` estendido: `health()`, `chat()` (parser SSE sobre Dio ResponseType.stream), conversas.
- `ai_chat_screen.dart` — bolhas com streaming ao vivo, indicador "Consultando seus dados…" durante
  tools, chips de sugestão, entrada por voz (speech_to_text pt-BR), histórico/exclusão de conversas
  em bottom sheet, renderizador próprio de markdown mínimo (negrito + listas; sem dependência nova).
- Rota `/ai-chat` acima da casca de navegação + atalho no AppBar do dashboard, visível apenas quando
  `aiAvailableProvider` (GET /ai/health) confirma a IA no ar — degradação graciosa.

Pendência consciente: validação de números do chat contra as telas com dados reais de produção fica
como verificação manual pós-deploy (as tools já são testadas unitariamente contra o mesmo banco).

**Ajustes pós-produção (2026-07-15, mesmo dia)** — aprendizados do primeiro uso real:
1. `aiAvailableProvider` (app) cacheava `false` para sempre após uma falha transitória no boot,
   escondendo o ícone da Hope — agora se reavalia sozinho (1 min indisponível / 10 min ok) e o
   pull-to-refresh do dashboard força nova checagem.
2. O modelo passava o **nome** da conta ("Débito") no `account_id` (UUID) → zod rejeitava → loop de
   desculpas. Correção estrutural em `tools/shared.js` (`resolveRefId`): filtros de conta/cartão/
   categoria aceitam **id ou nome** (igualdade > correspondência parcial, escopo do usuário);
   referência genérica ("essa conta") resolve sozinha com uma única opção, e com várias devolve
   erro instruindo o modelo a perguntar; nome não encontrado devolve as opções disponíveis para o
   modelo se corrigir na mesma rodada. Lição (validada com smoke no qwen3 real): o 8B **não resolve
   anáfora** ("nessa conta" → passa "essa conta" literal) nem com prompt diretivo — a tolerância
   precisa estar na ferramenta, não no prompt.

### Etapa 3 — Ações com confirmação: escrita em duas fases (M/G)

O chat passa a *fazer*, não só responder — com o usuário sempre no controle.

- Write tools: `create_transaction`, `update_transaction`, `pay_transaction` (baixa, com
  multa/juros como já suportado), `create_transfer`, `upsert_budget_item`, `create_goal`,
  `add_goal_contribution`, `create_category`.
- Fluxo em duas fases:
  1. O agente chama a write tool → em vez de executar, cria uma linha em **`ai_actions`**
     (`status: proposed`, payload completo, conversation_id, expira em 15 min) e devolve ao chat
     um **card de confirmação** (valor, conta, categoria, data — tudo visível).
  2. Usuário toca "Confirmar" → `POST /ai/actions/:id/confirm` → executa via `syncRepo`
     (auditoria automática) → responde com a entidade criada → app dispara sync pull.
     "Recusar" → `status: rejected` (vira sinal de qualidade).
- Regras: papéis de família respeitados (viewer não propõe escrita); exclusões e operações em lote
  sempre exigem confirmação; sem auto-confirmação nesta etapa (avaliar depois como opt-in para
  ações de alta confiança).
- Voz unificada: o fluxo de voz passa a poder usar o mesmo pipeline (frase → proposta → confirmação),
  mantendo o formulário pré-preenchido como alternativa.

**Pronto quando**: "lança 50 reais de mercado ontem no Nubank" cria a proposta, o card confirma,
a transação aparece no app após o sync e tudo está em `audit_logs` + `ai_actions`.

#### Resultado da Etapa 3 (2026-07-15)

**Backend**
- 8 write tools adicionadas ao catálogo único: criação/alteração/baixa de lançamento,
  transferência, item de orçamento, meta, aporte e categoria. Todas validam ids ou nomes dentro
  do escopo e somente criam propostas — nenhuma tool grava dados financeiros diretamente.
- Migration `ai_actions` com payload e resumo completos, vínculo à conversa/mensagem, expiração
  em 15 minutos e estados `proposed`, `confirmed`, `rejected`, `expired` e `failed`.
- `POST /ai/actions/:id/confirm|reject`; confirmação idempotente por mudança condicional de estado,
  revalidação de escopo e execução via `syncRepo`, mantendo `audit_logs` e o pull incremental.
- Papéis familiares revalidados na proposta e na confirmação; `viewer` não escreve. Baixas aceitam
  juros/multa separados, transferências geram o par débito/crédito e aportes atualizam a meta e
  criam o lançamento correspondente.
- Barreira de evidência no agente: perguntas e ações financeiras não podem produzir resposta final
  sem uma tool financeira bem-sucedida no turno atual. Tentativas sem consulta são descartadas antes
  do SSE; resultados vazios não podem ser completados com exemplos ou suposições.
- Consultas temporais inequívocas de lançamentos, despesas e receitas usam roteamento determinístico:
  o backend executa e formata `list_transactions` sem depender da escolha do modelo, inclusive em
  perguntas repetidas, resultados vazios e períodos como "últimos 7 dias". O filtro
  `on_credit_card` representa qualquer cartão quando nenhum nome específico é citado. Suíte do
  backend: **102 testes verdes**.

**App**
- O SSE ganhou o evento `action`; o chat renderiza card com todos os campos, prazo e botões
  Confirmar/Recusar. Após confirmar, dispara `syncNow()` para refletir a mudança localmente.
- Cards persistem no histórico com o desfecho. A entrada por microfone do chat usa o mesmo pipeline
  frase → proposta → confirmação; o formulário de voz preexistente continua como alternativa.
  `flutter analyze` sem alertas e **75 testes verdes** no app.

### Etapa 6 — Servidor MCP oficial (M) ✅ **concluída em 2026-08-06**

Expor o registro de tools como um **servidor MCP real** (Streamable HTTP/JSON-RPC), tornando o HopeCash
operável por qualquer host MCP — Claude Desktop, Claude Code, IDEs, outros agentes.

#### Resultado da Etapa 6 (2026-08-06)

**Backend**
- `modules/ai/mcp.server.js` — servidor completo com `initialize`, `tools/list` e `tools/call` (JSON-RPC 2.0);
  valida PATs no auth layer, bloqueia `push_transactions` do MCP.
- Escritos em **duas fases** mantidos via rota REST existente `POST /ai/actions/:id/confirm`.
- `GET /api/v1/pat` + `POST /pat` reusam endpoint `/mcp` — já exposto como `router.use('/mcp', mcpRouter)`.
- PAT service (Scopes MCP): novos tipos `mcp_read` (`["read"]`) e `mcp_write` (`["read", "write"]`).
  Migration com coluna `kind` (padrão `'push_transactions'`), scopes calculados automaticamente.
- listPats retorna `kind`, `last4` (últimos 4 do hash) e `scopes`.
- `ai.routes.ts`: importação + rota `/mcp`. Rotas temporárias `/ai/tools GET/POST` removidas de produção.
- Testado: endpoint funciona com JWT ou PAT — auth layer unificado via middleware auth_pat.js.

**Patente para hosts MCP**: escopo mcp_write dá acesso a todas as tools (incluindo escrita proposta → confirmação).

#### Resultado Etapa 4 (pendência futura)

A IA que trabalha sem ser perguntada — o maior valor prático para o usuário comum.

- **Motor de fatos** (`modules/ai/insights/facts.js`, 100% SQL): variação por categoria vs média
  dos últimos 3 meses, orçamento (estourado/quase), contas atrasadas e a vencer, taxa de poupança,
  gasto atípico (z-score simples por categoria), evolução de dívidas/metas, fatura vs limite.
- **Narrador** (LLM, structured output): fatos → 3 a 5 insights acionáveis
  `{ title, body, severity, category, cta }` em pt-BR natural.
- Entrega:
  - Card "Insights da Hope" no dashboard (novo endpoint `GET /ai/insights`).
  - `notifications` com novos tipos `ai_insight` / `ai_digest` (reusa toda a UI de notificações).
  - Resumo mensal automático no fechamento do mês; checagem semanal leve.
  - Digest opcional por e-mail (mailer já existe).
- Agendador: `node-cron` in-process no container da API (instância única — sem necessidade de locks).
- Cada insight tem ação "Explicar" → abre o chat com o contexto carregado.

**Pronto quando**: virada de mês gera digest coerente com os números do dashboard; insights aparecem no card e nas notificações.

### Etapa 5 — Categorização e importação inteligentes (M)

- **Importação**: ao criar um `import_batch`, um passo assíncrono sugere categoria para cada
  `import_item` (preenche `suggested_category_id`) usando batch com structured outputs e few-shot
  do histórico do próprio usuário (descrição → categoria mais frequente). A tela de revisão já
  exibe sugestões — só melhora a qualidade.
- **Notificações bancárias**: fallback LLM quando nenhuma `notification_rule` casa — alimenta a
  tela de sugestões existente (nunca cria lançamento direto).
- **Lançamentos sem categoria**: sugestão em massa ("12 lançamentos sem categoria — categorizar?").
- **Aprendizado**: quando o usuário corrige repetidamente a mesma coisa, propor uma
  `categorization_rule` ("Sempre que contiver 'UBER' → Transporte?") — regra determinística criada
  com consentimento, reduzindo dependência do LLM com o tempo.

**Pronto quando**: importar um OFX real preenche sugestões com boa taxa de acerto e o fallback de notificação funciona com regra desativada.

### Etapa 6 — Servidor MCP oficial (M)

Expor o registro de tools como um **servidor MCP real** (Streamable HTTP), tornando o HopeCash
operável por qualquer host MCP — Claude Desktop, Claude Code, IDEs, outros agentes.

- Endpoint `/api/v1/mcp` implementando o protocolo (initialize, tools/list, tools/call) sobre o
  registro existente — as tools já têm nome/descrição/JSON Schema no formato certo.
- Autenticação por **token pessoal (PAT)**: gerado em Configurações, com escopo `read` ou
  `read+write`, revogável, hasheado no banco (mesmo padrão dos refresh tokens).
- Escrita via MCP segue as duas fases: a tool de escrita devolve a proposta e existe uma tool
  `confirm_action` — o host externo também precisa confirmar explicitamente.
- Documentar em `docs/MCP.md` (exemplo de configuração no Claude Desktop).

**Pronto quando**: do Claude Desktop, "quanto gastei este mês?" responde e "lance X" propõe/confirma/cria, tudo escopado ao dono do token.

### Etapa 7 — Backlog avançado (priorizar conforme uso real)

- **Proposta de orçamento**: gerar `budget_items` do próximo mês a partir do histórico, com um clique.
- **Simulador de dívidas**: estratégias avalanche/bola de neve com narração ("quitando X primeiro, você economiza R$ Y em juros").
- **OCR enriquecido**: texto OCR do comprovante → itens estruturados em `ocr_data` (LLM parse).
- **Detecção de assinaturas**: recorrências implícitas nas transações ("você paga R$ 39,90/mês em…").
- **Digest familiar**: resumo semanal por membro para famílias.
- **Busca semântica**: embeddings (`/api/embed` do Ollama) para "aquela compra da farmácia em maio".
- **Retaguarda**: painel de telemetria da IA — latência, erros, taxa de confirmação/rejeição de ações por tipo, uso por modelo.

### Voz da Hope — perfil “Hope Velvet” (2026-07-16)

- Kokoro-FastAPI `v0.6.0` em CPU no servidor TTS privado (definido por `TTS_URL`), isolado do uso de VRAM do Ollama.
- Voz feminina combinada `pf_dora(2)+af_bella(1)`, velocidade `0.96`: dicção pt-BR com timbre mais claro, caloroso e elegante.
- Respostas terminadas em `?` recebem uma curva acústica ascendente nos últimos 600 ms via Rubber Band, com preservação de formantes; o timbre do restante da fala não é alterado.
- O Coqui/XTTS existente em `:8085` permanece como contingência automática.
- Pergunta iniciada por voz reproduz a resposta automaticamente; pergunta digitada oferece “Ouvir resposta”.
- O app recebe áudio apenas pelo endpoint autenticado `POST /ai/speech`; nenhum dado vai para serviços externos.

## 5. Transversal (vale para todas as etapas)

| Tema | Diretriz |
|---|---|
| LGPD/privacidade | Tudo on-premises; opt-out de IA em Configurações; conversas excluíveis pelo usuário; export inclui dados de IA |
| Auditoria | Toda execução de write tool passa por `syncRepo` → `audit_logs`; `ai_actions` guarda proposta e desfecho |
| Qualidade | Golden set pt-BR (frases → tool calls esperadas; perguntas → números esperados) rodando no vitest com fixtures; prompts versionados |
| Resiliência | Timeout + retry no cliente; circuit breaker simples (N falhas → IA "indisponível" por M min); UI esconde recursos quando `/ai/health` falha |
| Telemetria | Log estruturado (pino): modelo, latência, tokens, tool calls, resultado — base para o painel da Etapa 7 |
| Modelos | `qwen3:8b` é o padrão validado (100% no golden set, ver resultado da Etapa 0); reavaliar modelo maior para `chat` na Etapa 2; temperature 0 para tools/extração, ~0.4 para narrativa |
| Docs | Cada etapa atualiza `openapi.yaml`, `docs/API.md` e este roadmap (status abaixo) |

## 6. Ordem, dependências e status

```
Etapa 0 ──► Etapa 1 ──► Etapa 2 ──► Etapa 3 ──► Etapa 6
                          │
                          ├──► Etapa 4 (após 1; melhor após 2)
                          └──► Etapa 5 (independente de 2/3)
```

| Etapa | Tamanho | Status |
|---|---|---|
| 0 — Fundação Ollama | P | ✅ concluída em 2026-07-15 — servidor atualizado, `qwen3:8b` validado com 100% no golden set |
| 1 — Toolbox leitura | M | ✅ concluída em 2026-07-15 — 13 tools, 80 testes verdes |
| 2 — Chat Hope (leitura) | M/G | ✅ concluída em 2026-07-15 — agente SSE + tela de chat; 87 testes verdes |
| 3 — Ações com confirmação | M/G | ✅ concluída em 2026-07-15 — 8 write tools, cards no chat e execução auditada em duas fases |
| 4 — Insights proativos | M | ⬜ não iniciada |
| 5 — Categorização inteligente | M | ⬜ não iniciada |
| 6 — Servidor MCP | M | ✅ concluída em 2026-08-06 — `mcp.server.js` (initialize, tools/list, tools/call JSON-RPC 2.0), PAT com escopos `read`/`write`, rota `/api/v1/ai/mcp/methods`, atalho `/ai/tools` removido de produção, docs/in MCP.md |
| 7 — Backlog avançado | — | ⬜ backlog |
