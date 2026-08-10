# HopeCash — API REST

Base: `http://localhost:3000/api/v1` · Documentação interativa completa: **Swagger UI em `/api/docs`** (gerada de `backend/src/docs/openapi.yaml`).

Autenticação: `Authorization: Bearer <access_token>`. Erros seguem o envelope `{ "error": { "code", "message", "details?" } }`.

## Autenticação

| Método | Rota | Descrição |
|---|---|---|
| POST | `/auth/register` | Cadastro (name, email, password) |
| POST | `/auth/login` | Login → access + refresh token |
| POST | `/auth/refresh` | Rotaciona refresh token |
| POST | `/auth/logout` | Revoga a sessão atual |
| POST | `/auth/forgot-password` | Gera token de recuperação |
| POST | `/auth/reset-password` | Redefine senha com token |

## Usuário e família

| Método | Rota | Descrição |
|---|---|---|
| GET/PUT | `/users/me` | Perfil |
| GET | `/users/me/export` | Exportação LGPD (JSON completo) |
| DELETE | `/users/me` | Exclusão definitiva da conta |
| GET | `/users/me/sessions` · DELETE `/users/me/sessions/:id` | Sessões ativas / logout remoto |
| CRUD | `/families` · `/families/:id/members` | Grupos familiares |
| POST | `/families/:id/invites` · POST `/families/invites/accept` | Convites |

## Recursos sincronizáveis (CRUD padrão)

`GET /` (filtros `updated_since`, `include_deleted`, paginação) · `GET /:id` · `POST /` (aceita `id` UUID do cliente) · `PUT /:id` (controle otimista por `version`) · `DELETE /:id` (soft delete)

`/accounts` · `/cards` · `/cards/:id/invoices` · `/categories` · `/categories/:id/subcategories` · `/transactions` · `/budgets` · `/budgets/:id/items` · `/goals` · `/debts` · `/investments` · `/rules/categorization` · `/rules/notification` · `/notifications`

`/notifications` tem um atalho extra: `PATCH /notifications/:id/read` marca como lida sem precisar montar o PUT completo com `version`.

### Operações específicas

| Método | Rota | Descrição |
|---|---|---|
| POST | `/accounts/transfer` | Transferência entre contas (par atômico) |
| GET | `/accounts/:id/statement` | Extrato com saldo corrente |
| POST | `/transactions/installments` | Compra parcelada (N parcelas) |
| POST | `/cards/:id/invoices/:invoiceId/pay` | Pagamento de fatura |
| GET | `/cashflow?from&to&granularity=day\|week\|month\|year` | Fluxo de caixa realizado + projetado |
| GET | `/dashboard` | Todos os indicadores do painel |
| GET | `/budgets/:id/summary` | Previsto × realizado por categoria |
| POST | `/imports` (multipart CSV/OFX/PDF) | Extrato: cria lote de revisão. Fatura: cria/retoma conciliação por hash e executa análise bidirecional |
| GET | `/imports/:id` | Lote, itens enriquecidos, candidatos e resumo financeiro projetado |
| PUT | `/imports/:id/items/:itemId` | Edita item ou registra decisão/associação manual |
| POST | `/imports/:id/decisions/bulk` | Aplica `create`, `ignore`, `keep` ou `remove` a vários itens |
| PUT | `/imports/:id/official-total` | Confirma o total oficial em centavos quando não extraído |
| POST | `/imports/:id/analyze` | Sincroniza a análise com as transações atuais, preservando associações manuais |
| POST | `/imports/:id/cancel` · `/imports/:id/resume` | Cancela ou retoma uma conciliação sem perder decisões |
| POST | `/imports/:id/confirm` | Extrato: comportamento anterior. Fatura: aplicação atômica e idempotente, bloqueada se a diferença não for zero |
| POST | `/ai/parse-transaction` | Interpreta frase falada (`{transcript}`) e devolve lançamento estruturado com ids do usuário — LLM local via Ollama (`OLLAMA_URL`); 503 se indisponível |
| POST | `/ai/speech` | Converte `{text}` em áudio com a voz local “Hope Velvet” (`pf_dora(2)+af_bella(1)`, velocidade 0,96; Coqui como contingência); autenticado, sem serviços externos |
| POST | `/ai/chat` | Chat SSE da Hope; pode emitir eventos `action` com propostas de escrita |
| POST | `/ai/actions/:id/confirm` | Confirma e executa uma proposta ainda válida via `syncRepo` |
| POST | `/ai/actions/:id/reject` | Recusa uma proposta sem alterar dados financeiros |

## Sincronização

| Método | Rota | Descrição |
|---|---|---|
| POST | `/sync/push` | Lote de operações offline `{deviceId, operations:[{operationId, entity, entityId, op, payload, baseVersion, clientUpdatedAt}]}` → resultado por operação |
| GET | `/sync/pull?since=<cursor>&entities=a,b` | Alterações incrementais por entidade + novo cursor |

Detalhes do protocolo em [ARCHITECTURE.md §3](ARCHITECTURE.md).

## Notificações push (Firebase Cloud Messaging)

| Método | Rota | Descrição |
|---|---|---|
| POST | `/push/devices` | Registra/atualiza (idempotente pelo token) o dispositivo push do usuário |
| POST | `/push/devices/deactivate` | Desativa o token no logout |
| GET | `/push/devices` | Lista os dispositivos do usuário (sem expor o token completo) |
| GET/PUT | `/push/preferences` | Preferências de notificação (opt-in por categoria, antecedência, fuso, `email_notifications_enabled`) |

`email_notifications_enabled` (bool, default `true`) controla o fallback por e-mail: quando o usuário não tem nenhum dispositivo push ativo, as mensagens (campanha ou automática) são enviadas por e-mail em vez de descartadas — desligando esse campo, nada é enviado nesse cenário.

Configuração completa (FlutterFire, VAPID, APNs pendente) em [FLUTTERFIRE.md](FLUTTERFIRE.md).

### Retaguarda — campanhas de notificação

Criação/edição/listagem/prévia/estatísticas disponíveis para `admin` e `superuser`; envio, agendamento, cancelamento, exclusão, reenvio e reprocessamento restritos a `superuser`.

| Método | Rota | Descrição |
|---|---|---|
| GET/POST | `/retaguarda/notifications` | Lista (filtro `status`, paginação) / cria rascunho |
| GET/PUT | `/retaguarda/notifications/:id` | Detalhe / edita (somente rascunho ou agendada) |
| DELETE | `/retaguarda/notifications/:id` | Exclui a campanha e seu histórico de entregas (bloqueado enquanto `processing`) |
| GET | `/retaguarda/notifications/:id/preview` | Alcance estimado (destinatários/dispositivos por plataforma + `email_fallback_total`: quantos destinatários elegíveis não têm dispositivo ativo e receberão por e-mail), sem enviar |
| GET | `/retaguarda/notifications/:id/stats` | Contadores e falhas recentes de entrega |
| POST | `/retaguarda/notifications/:id/send` | Envia imediatamente |
| POST | `/retaguarda/notifications/:id/schedule` | Agenda `{date, time, timezone}` (local) → gravado em UTC |
| POST | `/retaguarda/notifications/:id/cancel` | Cancela rascunho ou agendamento |
| POST | `/retaguarda/notifications/:id/resend` | Duplica como um novo rascunho e envia imediatamente, reavaliando destinatários/preferências atuais (não reaproveita o id nem as estatísticas da campanha original) |
| POST | `/retaguarda/notifications/:id/reprocess` | Reprocessa falhas temporárias (dispositivo ainda ativo) |

A pesquisa paginada de usuários para o público "selecionado" reutiliza `GET /retaguarda/app-users?search=`.

### Retaguarda — mensagens push automáticas

Gestão das mensagens disparadas sozinhas pelo scheduler (avisos de vencimento, insights financeiros, dicas da Hope) — diferente das campanhas manuais acima. Leitura liberada a `admin` e `superuser`; edição restrita a `superuser`.

| Método | Rota | Descrição |
|---|---|---|
| GET | `/retaguarda/automation-rules` | Lista as três regras (`due_reminder`, `financial_insight`, `tip`) |
| PUT | `/retaguarda/automation-rules/:messageType` | Liga/desliga, ajusta `frequency_days` e (exceto `due_reminder`) `title`/`body`/`config` |

`frequency_days` significa antecedência (dias antes do vencimento) para `due_reminder`, e intervalo mínimo entre envios ao mesmo usuário para `financial_insight`/`tip`. Detalhes de cada tipo em [ARCHITECTURE.md](ARCHITECTURE.md).
