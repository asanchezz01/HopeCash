# Integração MCP (Etapa 6) — HopeCash

## Visão geral

O HopeCash expõe um **servidor MCP oficial** que permite hosts externos (Claude Code, VS Code, outros agentes) consumirem as ferramentas financeiras da Hope diretamente.

- **Endpoint** (transporte HTTP "Streamable" — uma única URL para a sessão inteira): `POST https://<seu-dominio>/api/v1/ai/mcp`
  - `initialize`, `notifications/initialized`, `tools/list` e `tools/call` são todos JSON-RPC 2.0 enviados para essa mesma URL — é isso que hosts reais (Claude Code, Claude Desktop) fazem.
  - `/api/v1/ai/mcp/initialize` e `/api/v1/ai/mcp/methods` continuam funcionando como aliases (compatibilidade com os exemplos de curl abaixo e com configurações antigas), mas **não use o endpoint `/initialize` separado ao configurar um host MCP real** — ele só entende `initialize`, não os outros métodos.
- **Autenticação**: duas formas, o host escolhe qual usar —
  - **Bearer estático**: Personal Access Token (PAT) com escopo `mcp_read` ou `mcp_write`, gerado em Mais → Tokens de API no app (Claude Code funciona assim).
  - **OAuth 2.1** (Authorization Code + PKCE, com registro dinâmico de cliente): necessário para hosts que exigem OAuth para MCP remoto, como o ChatGPT. Ver seção própria abaixo.
- **Protocolo**: JSON-RPC 2.0 sobre HTTP
- **CORS**: `/.well-known/*`, `/api/v1/oauth/*` e `/api/v1/ai/mcp*` aceitam qualquer origem — hosts (ChatGPT, Grok, Claude) costumam testar a conexão via `fetch()` direto do próprio domínio deles, inclusive antes de qualquer OAuth (ex.: o botão "testar conexão" de um conector). Seguro porque a autenticação aqui é sempre um Bearer explícito, nunca cookie — CORS não protege nada que um token já vazado não exporia via curl direto de qualquer forma.

## Tipos de token PAT disponíveis

| Tipo | Escopo | Uso |
|---|---|---|
| `mcp_read` | `["read"]` | Apenas leitura — saldos, transações, orçamentos, etc. |
| `mcp_write` | `["read", "write"]` | Leitura + escrita (executa direto numa chamada — ver seção "Executar uma tool de escrita") |
| `push_transactions` | `["push_transactions"]` | Apenas criação de lançamentos via `/api/transactions/...` (**NÃO** acessa MCP) |

## Configurar Claude Code para usar MCP

Claude Code conecta-se ao servidor MCP via HTTP transport. No arquivo de configuração do Claude Code:

```json
{
  "mcpServers": {
    "hopecash": {
      "url": "https://<dominio>/api/v1/ai/mcp",
      "authToken": "hc_pat_xxxxxxxx"
    }
  }
}
```

Ou via CLI:

```bash
claude mcp add --transport http hopecash https://<dominio>/api/v1/ai/mcp \
  --header "Authorization: Bearer hc_pat_xxxxxxxx"
```

## Configurar ChatGPT (ou outro host que exija OAuth)

O ChatGPT só conecta MCP remoto via OAuth — não aceita colar um Bearer token estático. O HopeCash implementa um Authorization Server mínimo (OAuth 2.1: Authorization Code + PKCE S256, Dynamic Client Registration — RFC 7591/6749/7636/8414/9728) só para isso.

Basta apontar o host para a URL do MCP (`https://<dominio>/api/v1/ai/mcp`) — a descoberta é automática:

1. O host lê `https://<dominio>/.well-known/oauth-protected-resource/api/v1/ai/mcp` e descobre o Authorization Server.
2. Lê `https://<dominio>/.well-known/oauth-authorization-server` e descobre `authorization_endpoint`, `token_endpoint` e `registration_endpoint`.
3. Se registra sozinho via `POST /api/v1/oauth/register` (client público, sem `client_secret` — PKCE cobre a segurança da troca do code).
4. Abre o navegador em `GET /api/v1/oauth/authorize` — você faz login com seu e-mail/senha do HopeCash e escolhe **somente leitura** ou **leitura e escrita**.
5. O host troca o `code` por um `access_token` em `POST /api/v1/oauth/token`.

O `access_token` emitido **é um PAT normal** — aparece em Mais → Tokens de API no app, com o nome `OAuth: <nome do host>`, e pode ser revogado por lá a qualquer momento (não existe endpoint `/revoke` separado).

**Limitação atual**: sem suporte a `refresh_token` — o token emitido segue a mesma política de expiração dos PATs manuais (por padrão, nunca expira). Se o host tentar `grant_type=refresh_token`, a resposta é `unsupported_grant_type`.

Ou, se preferir usar curl diretamente:

```bash
curl -X POST https://<dominio>/api/v1/ai/mcp/initialize \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer hc_pat_xxxxxxxx" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "initialize"}'
```

## Inicializar a sessão

```bash
curl -X POST https://<dominio>/api/v1/ai/mcp/initialize \
  -H "Authorization: Bearer hc_pat_xxxxxxxx" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "initialize"}'
```

Resposta esperada:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": { "tools": { "listChanged": false } },
    "serverInfo": { "name": "hopecash-mcp", "version": "1.0.0" }
  }
}
```

## Listar tools disponíveis

```bash
curl -X POST https://<dominio>/api/v1/ai/mcp/methods \
  -H "Authorization: Bearer hc_pat_xxxxxxxx" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

Exemplo de resposta:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "get_balances",
        "inputSchema": { ... },
        "description": "Retorna o saldo por conta...",
        "write": false
      }
    ]
  }
}
```

## Executar uma tool de leitura

```bash
curl -X POST https://<dominio>/api/v1/ai/mcp/methods \
  -H "Authorization: Bearer hc_pat_xxxxxxxx" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "get_balances",
      "arguments": {}
    }
  }'
```

## Executar uma tool de escrita

Uma tool de escrita chamada via MCP **executa direto, numa única chamada** — não existe uma segunda etapa de confirmação nesse caminho:

```bash
curl -X POST https://<dominio>/api/v1/ai/mcp/methods \
  -H "Authorization: Bearer hc_pat_xxxxxxxx" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "create_transaction",
      "arguments": {
        "type": "expense",
        "description": "Almoço mercado",
        "amount": 85.50,
        "date": "2026-08-01"
      }
    }
  }'
```

A resposta já vem com `status: "confirmed"` e o `result` da execução (ex.: o lançamento criado) — não `status: "proposed"`.

**Por quê**: internamente a tool ainda passa por `proposeAction` → `confirmAction` (a mesma dupla checagem de sempre — `assertWritable`, versão otimista, etc.), mas as duas etapas acontecem na mesma requisição HTTP. Hosts MCP (ChatGPT, Claude) já pedem aprovação do usuário na própria interface deles antes de chamar uma tool marcada como escrita — essa é a barreira de segurança real nesse caminho, e só chamam tools listadas em `tools/list` (não endpoints REST arbitrários), então uma segunda tool de confirmação nunca teria como ser descoberta/chamada de forma confiável. Uma versão anterior exigia duas chamadas MCP separadas no tempo (propor → `confirm_pending_action`); isso causou `"Session terminated"` do lado do ChatGPT na janela entre as duas — corrigido fundindo em uma chamada só.

O chat interno da Hope (no app) **não muda**: lá a IA ainda só propõe (`ai_actions` com `status: "proposed"`), e a confirmação continua sendo sempre um clique humano no card da conversa, via `POST /api/v1/ai/actions/${ACTION_ID}/confirm` (ou `/reject`) — esse endpoint REST segue existindo e funcionando exatamente como antes, só não é mais o caminho usado por hosts MCP.

## Conta de destino em `create_transaction`

Uma receita ou despesa **nunca** é criada sem destino. Sem conta nem cartão, o lançamento aparece no extrato mas não move saldo nenhum — vira um registro órfão que o usuário só descobre ao conferir a conta.

Como `account_id` é opcional no schema (e o modelo simplesmente omite quando não sabe), a regra é:

| Situação | Resultado |
|---|---|
| `card_id` informado | Segue no cartão; `account_id` fica nulo, o destino é a fatura |
| `account_id` válido | Usa a conta informada |
| `account_id` ausente | Usa a conta de débito principal e **avisa** |
| `account_id` não identificável | Usa a conta de débito principal e **avisa** (em vez de falhar) |
| Nenhuma conta de débito ativa | Erro pedindo para cadastrar uma conta no app |

"Conta de débito principal" = a primeira conta ativa na ordem `checking → digital → wallet → cash → savings`, desempatando pela mais antiga. Contas `investment` nunca entram — lançar despesa corriqueira ali distorce saldo e projeção.

A mesma regra vale fora do MCP, em `core/transactionDestination.js`: **todo lançamento pago** precisa de conta ou cartão, em qualquer caminho de escrita. Previsto não precisa — ainda não movimentou saldo, e a conta entra na baixa. A única exceção é a baixa de variação de orçamento (`notes` com prefixo `hopecash:budget_variance:`), que fecha a diferença sem mover dinheiro. Onde a regra é aplicada:

- **REST / `syncRepo`** (app online, IA, `/installments`): recusa com 400 — o chamador vê o erro e corrige.
- **`POST /sync/push`**: **completa** com a conta de débito principal em vez de recusar. Rejeitar aqui apagaria um lançamento que o usuário já viu salvo no aparelho, e versões do app em campo permitem salvar sem forma de pagamento. Só recusa quando não há conta nenhuma para atribuir.

Quando o destino é escolhido pelo sistema, a resposta do `tools/call` traz:

```json
{
  "status": "confirmed",
  "assumed_account": { "name": "Nubank", "reason": "nenhuma conta foi informada" },
  "notice": "Lançado em \"Nubank\" porque nenhuma conta foi informada. Confirme com o usuário se a conta está correta."
}
```

O host deve repassar esse aviso ao usuário — via MCP não existe card de confirmação, então essa é a única chance de a pessoa saber qual conta foi usada.

## Tools de escrita disponíveis

| Tool | Descrição | Escopo |
|---|---|---|
| `create_transaction` | Lançar receita/despesa | write |
| `update_transaction` | Alterar lançamento existente | write |
| `pay_transaction` | Dar baixa em lançamento | write |
| `create_transfer` | Transferência entre contas | write |
| `upsert_budget_item` | Criar/atualizar item de orçamento | write |
| `create_goal` | Criar meta financeira | write |
| `add_goal_contribution` | Adicionar aporte à meta | write |
| `create_category` | Criar categoria nova | write |

## Log das chamadas (tabela `mcp_logs`)

Toda chamada JSON-RPC que chega ao servidor MCP é registrada na tabela `mcp_logs` — trilha **persistente**, ao contrário do `docker logs` do container, que some no próximo deploy.

| Coluna | Observação |
|---|---|
| `user_id` | Dono do token; join com `users` no endpoint da retaguarda |
| `client_name` | Nome do PAT (`OAuth: ChatGPT`, `Claude`…) — na prática identifica o host |
| `method` | `initialize`, `tools/list`, `tools/call`, `notifications/*` |
| `tool_name` | Preenchido em `tools/call`, **inclusive quando a tool não existe** |
| `ok` / `status_code` / `error_code` / `error_message` | Resultado; `error_code` é o código JSON-RPC (`-32601`, `-32602`…) |
| `arguments` | Argumentos enviados pelo host, truncados em 2000 chars |
| `duration_ms`, `ip`, `user_agent`, `created_at` | |

**Guardamos os argumentos, nunca o resultado** — o resultado é o dado financeiro do usuário, e copiá-lo para cá só ampliaria a superfície LGPD sem ajudar no diagnóstico.

Duas coisas **não** entram na tabela, de propósito:

- O 401 de descoberta (host sondando sem token antes do OAuth) — não chega a ser uma sessão MCP; é passo normal do RFC 9728.
- PAT `push_transactions`, barrado no gate do `app.js` uma camada antes do router MCP.

Leitura pela retaguarda (exige login de retaguarda):

```bash
# últimas chamadas, com filtros opcionais
GET /api/v1/retaguarda/mcp-logs?user_id=&tool_name=&method=&only_errors=true&since=&until=&limit=50&offset=0

# agregado por tool — "o que está falhando"
GET /api/v1/retaguarda/mcp-logs/summary?since=&until=
```

> Ainda **não** existe tela na retaguarda para isso — só o endpoint. A tabela também não tem rotina de expurgo; se o volume crescer, criar um job de retenção.

## Segurança

- **Escopo do usuário**: todas as tools executam no escopo do proprietário do token (syncRepo).
- **Gate de PAT**: apenas tokens com tipo `mcp_read` ou `mcp_write` acessam o servidor MCP. Tokens `push_transactions` recebem 403 (`-32605`).
- **Escrita em duas fases**: hosts externos **não executam alterações diretamente** — a tool de escrita cria uma proposta em `ai_actions` que precisa de confirmação via `POST /api/v1/ai/actions/:id/confirm`.
- **Todos PATs são hasheados**: SHA-256 no banco e revogáveis a qualquer momento via `DELETE /api/v1/pat/$id`.

## Troubleshooting

### Erro 403 — "Este token PAT não tem escopo MCP" (erro -32605)
O token usado é do tipo `push_transactions`, que só permite criação de lançamentos via `/transactions` REST. Gere um novo PAT (`POST /api/v1/pat`) com `kind: "mcp_read"` ou `"mcp_write"`.

### Erro -32601 — "Tool não encontrada"
O nome da tool está incorreto. Use `tools/list` para ver a lista oficial.

### Erro -32602 — "Parâmetros inválidos"
Algum campo está fora do schema esperado. Verifique os tipos e campos obrigatórios no output de `tools/list`.

### A tela de login do OAuth parece travada — o botão não responde
Corrigido em 2026-08-08. Duas causas somadas, ambas do lado do navegador:

- A página não tinha **nenhum** retorno visual no submit. O POST leva ~300ms (bcrypt) e nesse intervalo nada mudava na tela — dentro do navegador embutido do ChatGPT isso é indistinguível de um botão quebrado. Caso real: 32 submissões em 40s, todas bem-sucedidas no servidor, cada uma emitindo um authorization code novo. Hoje o botão vira "Entrando…", fica desabilitado até a navegação acontecer, e volta ao normal com uma explicação se passarem 15s.
- O CSP global do helmet inclui `form-action 'self'`, que WebKit e Firefox aplicam também ao **redirect que segue o submit** — exatamente o redirect de volta para `chatgpt.com` que o OAuth exige. A tela de `/authorize` agora manda um CSP próprio liberando a origem do `redirect_uri` (que o servidor já validou contra os `redirect_uris` registrados do client).

Além disso, emitir um code novo agora invalida os anteriores pendentes do mesmo client+usuário — um clique repetido não deixa mais uma fila de codes válidos em aberto.

### Erro ao acessar `/api/v1/ai/mcp` diretamente de um app mobile
Esse endpoint é exclusivamente para **hosts MCP** (agentes). Apps clientes devem usar as rotas REST normais (`/ai/chat`, etc.).

## Status da Etapa 6

| Item | Status |
|---|---|
| MCP server (`initialize`, `tools/list`, `tools/call`) | ✅ Implementado em `modules/ai/mcp.server.js` |
| Middleware `requireMcpContext` — bloqueio de push_tokens | ✅ Consolidação aplicada (cobre `/initialize` + `/methods`) |
| Gate no v1 router (`app.js`) — permite MCP PATs passarem | ✅ Implementado |
| Scopes MCP no PAT service (`mcp_read` / `mcp_write`) | ✅ Implementado |
| Migration com coluna `kind` | ✅ Feita em `20260801000004_personal_access_tokens.js` |
| Rota `/api/v1/ai/mcp/methods` registrada | ✅ Registrada em `ai.routes.js` via `router.use('/mcp', mcpRouter)` |
| Remoção do TODO / rotas temporárias `GET/POST /ai/tools` | ✅ Feito em production |
| Docs de integração | ✅ Este arquivo |
| Escrita em duas fases via MCP funcionando de ponta a ponta | ✅ Corrigido — `proposeAction` exigia `conversation_id`, que hosts MCP nunca enviavam; `mcp.server.js` agora reaproveita/cria uma conversa técnica (`Hope MCP`) por usuário. O gate do `app.js` também liberou `/ai/actions/:id/confirm` e `/reject` para PATs `mcp_read`/`mcp_write` (a checagem de escopo continua em `assertWritable`) |
| Endpoint único (transporte HTTP "Streamable") | ✅ Corrigido — `initialize`/`notifications/initialized`/`tools/list`/`tools/call` respondem todos em `POST /api/v1/ai/mcp` (e no alias `/methods`); antes só `/initialize` entendia `initialize`, então hosts reais (que mandam tudo para uma única URL) falhavam já no handshake |
| Tela no app para o usuário gerar seu próprio PAT | ✅ `Mais → Tokens de API` (`app/lib/presentation/screens/api_tokens_screen.dart`) |
| OAuth 2.1 (Authorization Code + PKCE + Dynamic Client Registration) para hosts que exigem OAuth (ChatGPT) | ✅ `modules/oauth/` — `/api/v1/oauth/{register,authorize,token}` + `/.well-known/oauth-authorization-server` e `/.well-known/oauth-protected-resource/api/v1/ai/mcp`. Token emitido é um PAT normal (sem `refresh_token` nesta versão) |
| CORS aberto na superfície pública do OAuth (`/.well-known/*`, `/api/v1/oauth/*`) | ✅ Corrigido — a allowlist de CORS do resto da API bloqueava `fetch()` cross-origin do domínio do host MCP (ex. chatgpt.com) e a rejeição virava 500 genérico em vez de 403; agora essas rotas aceitam qualquer origem (sem credentials) |
| Escrita via MCP em uma única chamada (sem segunda etapa de confirmação) | ✅ Corrigido — 1ª tentativa foi adicionar tools `confirm_pending_action`/`reject_pending_action` separadas, mas duas chamadas MCP no tempo causaram `"Session terminated"` do lado do ChatGPT; agora `tools/call` de uma tool de escrita já propõe e confirma na mesma requisição. Chat interno da Hope no app continua em duas fases (clique humano no card), inalterado |
