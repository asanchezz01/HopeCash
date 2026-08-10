# HopeCash — Arquitetura

## 1. Visão geral

```
┌─────────────────────────────────────────────┐
│                Flutter App                  │
│        (Android / iOS / Web, pt-BR)         │
│                                             │
│  Presentation  ──  Riverpod + go_router     │
│  Domain        ──  Entidades + casos de uso │
│  Data          ──  Repositórios             │
│     ├── Local: Drift (SQLite)  ← fonte da   │
│     │          verdade no dispositivo       │
│     ├── Fila de operações pendentes         │
│     └── Remote: Dio → API REST              │
└──────────────────┬──────────────────────────┘
                   │ HTTPS + JWT
                   │ /sync/push  /sync/pull
┌──────────────────▼──────────────────────────┐
│           Backend Node.js (Express 5)       │
│  API REST versionada (/api/v1)              │
│  Auth JWT + refresh rotativo                │
│  Validação Zod · Rate limit · Auditoria     │
│  Módulos por domínio · Swagger/OpenAPI      │
└──────────────────┬──────────────────────────┘
                   │ Knex (migrations/seeds)
┌──────────────────▼──────────────────────────┐
│                  MySQL 8                    │
│  UUID + version + updated_at + soft delete  │
└─────────────────────────────────────────────┘
```

**Princípio central: local-first.** O app lê e grava sempre no banco local (Drift/SQLite). Toda escrita gera uma operação na fila de sincronização. O `SyncService` envia a fila (`push`) e busca alterações incrementais (`pull`) quando há conectividade. A UI nunca espera a rede.

## 2. Módulos do produto

| Módulo | Backend | App |
|---|---|---|
| Autenticação e sessões | `modules/auth` | `features/auth` |
| Usuários e perfis | `modules/users` | `features/settings` |
| Famílias, convites, permissões | `modules/families` | `features/family` |
| Contas bancárias e transferências | `modules/accounts` | `features/accounts` |
| Cartões de crédito e faturas | `modules/cards` | `features/cards` |
| Categorias/subcategorias/regras | `modules/categories`, `modules/rules` | `features/categories` |
| Receitas, despesas, parcelas, recorrência | `modules/transactions` | `features/transactions` |
| Orçamento mensal | `modules/budgets` | `features/budgets` |
| Fluxo de caixa e projeções | `modules/cashflow` | `features/cashflow` |
| Metas financeiras | `modules/goals` | `features/goals` |
| Dívidas e financiamentos | `modules/debts` | `features/debts` |
| Investimentos simples | `modules/investments` | `features/investments` |
| Importação de extrato e conciliação de fatura (CSV/OFX/PDF) | `modules/imports` | `presentation/screens/import_screen.dart` |
| Notificações bancárias (Android) | `modules/rules` (regras) | `features/bank_notifications` |
| OCR de notas/comprovantes | `modules/transactions` (anexos) | `features/receipts` |
| Dashboard e indicadores | `modules/dashboard` | `features/dashboard` |
| Alertas e notificações (caixa de entrada) | `modules/push/notificationsInbox.routes.js` | `presentation/screens` (via `/api/v1/notifications`) |
| Notificações push (FCM): dispositivos, preferências, campanhas, avisos de vencimento | `modules/push`, `modules/retaguarda/notifications.routes.js` | `core/services/push_notifications_service.dart` |
| Sincronização | `modules/sync` | `data/sync` |

## 3. Sincronização offline-first

### 3.1 Colunas de sincronização (todas as entidades sincronizáveis)

| Coluna | Papel |
|---|---|
| `id` (UUID v4, gerado no cliente) | Identidade global — permite criar offline sem colisão |
| `user_id` / `family_id` | Escopo de propriedade e partilha |
| `version` (int) | Incrementada pelo **servidor** a cada gravação aceita |
| `updated_at` | Carimbo do servidor; base do pull incremental |
| `deleted_at` | Soft delete — exclusões também sincronizam |
| `sync_status` (local) | `synced` \| `pending` \| `conflict` (só no SQLite do app) |

### 3.2 Fluxo de escrita no app

1. Usuário salva um lançamento → gravado no Drift com `sync_status = pending`.
2. Uma linha é adicionada em `pending_operations` (`entity`, `entity_id`, `op`, `payload`, `base_version`).
3. UI atualiza imediatamente (fonte local).
4. `SyncService` (disparado por conectividade, timer e pós-gravação) drena a fila em lote via `POST /api/v1/sync/push`.

### 3.3 Push e resolução de conflitos

O servidor processa cada operação de forma idempotente:

- `create`: insere se o `id` não existe; se já existe, trata como `update`.
- `update`/`delete`: compara `base_version` (versão que o cliente conhecia) com a `version` atual do servidor.
  - Iguais → aplica, `version++`, responde `applied`.
  - Servidor à frente → **conflito**: aplica *last-write-wins* pelo `client_updated_at`; a versão perdedora é preservada em `sync_operations` (payload completo) e em `audit_logs`. Responde `conflict_resolved` com o registro vencedor para o cliente convergir.
- Toda operação é registrada em `sync_operations` (auditoria + idempotência por `operation_id`).

### 3.4 Pull incremental

`GET /api/v1/sync/pull?since=<cursor>` retorna, por entidade, todos os registros do escopo do usuário/família com `updated_at > cursor` (incluindo soft-deleted) e um novo cursor (timestamp do servidor). O app aplica upsert/tombstone no Drift e persiste o cursor. Primeiro login = pull com `since=0` (bootstrap completo).

### 3.5 Garantias

- **Idempotência**: reenvio da mesma operação (mesmo `operation_id`) não duplica efeito.
- **Ordenação**: fila drenada em ordem de criação local; parcelamentos/transferências enviados como grupo.
- **Falha parcial**: resposta por operação; as aplicadas saem da fila, as demais permanecem.
- **Relógio**: `updated_at` autoritativo é sempre do servidor; o do cliente só desempata conflitos.

## 4. Segurança e privacidade (LGPD como premissa)

| Camada | Medida |
|---|---|
| Transporte | HTTPS obrigatório em produção (TLS ≥ 1.2; app recusa HTTP fora de debug) |
| Senhas | bcrypt (custo 12), política mínima de complexidade |
| Sessão | JWT de acesso curto (15 min) + refresh token rotativo (30 dias) armazenado **hasheado** em `user_sessions`; logout remoto revoga sessões por dispositivo |
| SQL Injection | Knex com bindings parametrizados em 100% das queries |
| XSS/CSRF | API stateless somente-JSON + Helmet; sem cookies de sessão |
| Rate limiting | Global + limite agressivo em `/auth/*` |
| Autorização | Escopo por `user_id`/`family_id` aplicado no repositório (nunca confiar no payload); papéis `owner/admin/member/viewer` por família |
| Dados locais | SQLite; tokens em `flutter_secure_storage` (Keychain/Keystore); campos sensíveis cifrados |
| Auditoria | `audit_logs` para toda escrita (quem, quando, o quê, de onde) |
| LGPD | Exportação completa dos dados (`GET /users/me/export`), exclusão definitiva (`DELETE /users/me` com purga agendada), soft delete, mínimo necessário nas notificações bancárias (só o texto interpretado, nunca o histórico bruto) |

### Leitura de notificações bancárias (Android)

Recurso **opt-in** via `NotificationListenerService`: permissão explícita do sistema, ativável por banco, prévia obrigatória antes de criar lançamento, regras de reconhecimento versionadas em `notification_rules`. Nada do texto bruto sai do dispositivo — apenas o lançamento confirmado pelo usuário. iOS/Web: alternativas são importação de extrato, atalhos de lançamento rápido e e-mail forwarding (roadmap).

## 5. Decisões técnicas

| Decisão | Escolha | Motivo |
|---|---|---|
| API | REST versionada (`/api/v1`) + OpenAPI | Requisito; simplicidade de cache/documentação |
| Query/migrations | Knex | SQL explícito, migrations versionadas, portável p/ SQLite nos testes |
| Validação | Zod | Schemas compartilháveis, mensagens claras |
| Estado no app | Riverpod | Testável, sem codegen obrigatório, escala bem |
| Banco local | Drift | Reativo (streams), type-safe, suporta Web (WASM) |
| Dinheiro | `DECIMAL(15,2)` no MySQL; centavos como inteiro no app | Sem erro de ponto flutuante |
| IDs | UUID v4 gerado no cliente | Criação offline sem coordenação |
| Multi-tenant | `user_id`/`family_id` em todas as tabelas + escopo forçado no acesso | Pronto para SaaS; isolamento por linha |

### Conciliação de fatura

`credit_card_invoice` usa o mesmo lote e a mesma tela da importação unificada, mas não executa importação automática. Antes do upload, o app sincroniza as operações pendentes. O servidor identifica o ciclo pelo cartão e vencimento, extrai o total oficial, compara itens da fatura com transações do ciclo e persiste decisões nos próprios `import_batches` e `import_items`.

O matching é determinístico, estável e um-para-um: tipo financeiro e valor em centavos são obrigatórios; data exata gera `exact_match`, e deslocamento de até três dias gera `probable_match`; descrição normalizada desempata e múltiplos candidatos equivalentes geram `ambiguous`. Pagamentos de fatura, transações canceladas, outros cartões e outros vencimentos não participam.

A confirmação revalida versões, decisões e totais, aplica criações/edições/soft deletes em uma única transação SQL e só conclui quando `total_oficial - total_projetado = 0` centavos. Hash SHA-256 do arquivo e estado do lote tornam upload repetido e retry idempotentes.

### Notificações push (Firebase Cloud Messaging)

Projeto Firebase único (`hopecash`) reutilizado em Android, iOS e Web/PWA — ver `docs/FLUTTERFIRE.md` para a configuração completa. No backend (`backend/src/modules/push/`):

- **Abstração de provedor** (`providers/`): `FirebasePushProvider` (produção, `firebase-admin`), `FakePushProvider` (testes, nunca acessa a rede) e `DisabledPushProvider` (dry-run quando `FIREBASE_ENABLED=false` ou mal configurado fora de produção). A fábrica em `providers/index.js` escolhe automaticamente pelo ambiente.
- **Modelo de dados**: `push_devices` (tokens por usuário/plataforma, múltiplos por usuário), `push_preferences` (opt-in por categoria + antecedência + fuso), `push_campaigns` (campanhas manuais da retaguarda), `push_automation_rules` (uma linha por tipo de mensagem automática — liga/desliga e frequência, ver abaixo) e `push_deliveries` (uma linha por tentativa de entrega, de campanha OU automática, com `idempotency_key` única). A tabela `notifications` (caixa de entrada) já existia e não foi alterada — são conceitos independentes.
- **Scheduler** (`scheduler.js`): um `setInterval` (`PUSH_SCHEDULER_INTERVAL_MS`) que a cada ciclo (1) reivindica campanhas agendadas cuja hora chegou, (2) roda os três workers de mensagem automática (avisos de vencimento, insights financeiros, dicas — cada um só age se sua regra estiver habilitada) e (3) despacha entregas pendentes. Idempotente e seguro com múltiplas instâncias: campanhas e entregas são "reivindicadas" por um único `UPDATE ... WHERE status = 'X'` (compare-and-swap otimista, sem lock global nem recurso específico de um SGBD), então só uma instância concorrente vence cada linha.
- **Retry**: falhas classificadas como permanentes (token inválido/revogado) desativam o dispositivo na hora; falhas temporárias (rede, indisponibilidade, limitação) entram em backoff exponencial com jitter (até 6 tentativas) antes de desistir.
- **Mensagens automáticas** (`services/dueReminderService.js`, `financialInsightService.js`, `tipService.js`) — cada uma controlada por uma linha em `push_automation_rules`, gerenciável na retaguarda em **Notificações → Mensagens automáticas** (liga/desliga, frequência e, quando aplicável, título/corpo):
  - *Avisos de vencimento*: aviso com antecedência configurável (padrão da regra, sobreposto pela preferência do usuário quando existir), no dia do vencimento e um único aviso de atraso (1 dia após — não repete diariamente).
  - *Insights financeiros*: verifica o orçamento pessoal do mês (reaproveita `getBudgetSummary` de `modules/budgets`) e alerta quando uma categoria de despesa atinge o limite configurado (`config.threshold_percent`, padrão 90%); respeita um intervalo mínimo entre envios ao mesmo usuário.
  - *Dicas da Hope*: para cada usuário elegível, monta um resumo financeiro agregado do mês (receitas/despesas, orçamento, saldo, dívidas e metas) e pede ao Ollama privado uma nova dica curta e personalizada. O conteúdo gerado é persistido na entrega para ser idêntico no push, no e-mail e nas retentativas; se a IA estiver indisponível ou devolver uma resposta inválida, usa o texto configurado na retaguarda como contingência. O prompt proíbe nomes, descrições, valores exatos e outros dados identificáveis no texto exibido na notificação.
  - Todo conteúdo automático é sempre genérico — sem valores/saldos/descrições (tela bloqueada não deve expor dados financeiros).
- **Deep links**: lista de permissão fixa (`deepLinks.js`, espelhada no app em `core/platform/push_deep_links.dart`) — nunca se aceita uma URL arbitrária vinda da retaguarda ou de um payload de push.
- **Fallback por e-mail** (`providers/emailNotificationProvider.js`, `emailTemplate.js`): quando um usuário elegível (campanha, aviso de vencimento, insight ou dica) não tem nenhum `push_devices` ativo, `enqueueForUser` (`services/deliveryService.js`) enfileira **uma** entrega com `channel = 'email'` e `device_id = null` em vez de uma por dispositivo — mesma tabela `push_deliveries`, mesmo `idempotency_key`, mesmo retry/backoff. O layout HTML (tabela + CSS inline para compatibilidade entre clientes, cor de marca `#16C784`) é gerado por `renderNotificationEmail` e enviado via `core/mailer.js` (mesmo SMTP `MAIL_*` do reset de senha) através da mesma abstração Real/Fake dos provedores de push (`getEmailNotificationProvider()`). O conteúdo é o mesmo texto seguro do push; nas dicas personalizadas, ele vem de `push_deliveries.notification_content`, sem valores, saldos ou descrições. Cada usuário pode desligar esse fallback individualmente (`push_preferences.email_notifications_enabled`, padrão ligado); se desligado e sem dispositivo ativo, nenhuma entrega é criada.
- **LGPD**: exclusão de conta remove `push_devices`, `push_preferences` e `push_deliveries` do usuário; exportação de dados inclui dispositivos e preferências. `push_automation_rules` é configuração global do sistema, não dado pessoal.

No app Flutter, `PushNotificationsService` (`core/services/push_notifications_service.dart`) inicializa o Firebase, pede permissão após o login (com contexto: diálogo explicando o motivo), registra/renova o token, escuta primeiro/segundo plano e abertura por notificação, e desativa o token no logout — sem interferir na captura local de notificações bancárias (`NotificationCapture`/`BankNotificationListenerService`), que é um mecanismo completamente separado.
