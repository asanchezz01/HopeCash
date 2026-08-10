# HopeCash — Modelo de Dados

Todas as tabelas de negócio carregam as **colunas de sincronização**: `id CHAR(36) PK` (UUID), `user_id`, `family_id NULL`, `created_at`, `updated_at`, `deleted_at NULL`, `version INT`. Valores monetários: `DECIMAL(15,2)`. Datas de competência: `DATE`; carimbos: `DATETIME(3)`.

## Identidade e família

- **users** — `name`, `email UNIQUE`, `password_hash`, `avatar_url`, `locale` (pt-BR), `currency` (BRL), `status` (active/blocked/pending_deletion), `password_reset_token`, `password_reset_expires_at`
- **user_sessions** — sessões de refresh token: `user_id`, `refresh_token_hash`, `device_name`, `ip`, `user_agent`, `expires_at`, `revoked_at`. Permite logout remoto por dispositivo.
- **families** — `name`, `owner_id → users`
- **family_members** — `family_id`, `user_id NULL` (null enquanto convite pendente), `invited_email`, `invite_token`, `role` (owner/admin/member/viewer), `status` (invited/active/removed), `permissions JSON`

## Contas e cartões

- **bank_accounts** — `name`, `bank_name`, `bank_code`, `agency`, `account_number`, `type` (checking/savings/investment/wallet/cash/digital), `initial_balance`, `initial_balance_date`, `color`, `icon`, `is_active`, `include_in_total`. Saldo atual = `initial_balance` + Σ transações realizadas (calculado, nunca armazenado).
- **credit_cards** — `name`, `issuer`, `limit_amount`, `closing_day`, `due_day`, `color`, `icon`, `is_active`, `default_account_id → bank_accounts` (débito da fatura). Melhor dia de compra = dia seguinte ao fechamento (derivado).
- **credit_card_invoices** — `card_id`, `reference_month DATE`, `closing_date`, `due_date`, `status` (open/closed/paid/partial), `total_amount`, `paid_amount`, `payment_transaction_id → transactions`

## Classificação

- **categories** — `name`, `type` (income/expense), `icon`, `color`, `is_system` (categorias padrão têm `user_id NULL` e `is_system=1`)
- **subcategories** — `category_id`, `name`, `icon`
- **categorization_rules** — `name`, `match_field` (description/amount/bank/card/merchant), `operator` (contains/equals/starts_with/regex/between), `match_value`, `match_value2` (faixa), `category_id`, `subcategory_id`, `tags JSON`, `priority`, `is_active`
- **notification_rules** — reconhecimento de notificações bancárias: `bank_package` (ex.: `com.nu.production`), `bank_name`, `event_type` (pix_in/pix_out/debit/credit/payment/transfer_in/withdrawal), `pattern` (regex com grupos nomeados `valor`, `estabelecimento`), `is_active`

## Movimentações

- **transactions** — o coração do sistema:
  - `type` (income/expense/transfer), `description`, `notes`
  - Valores: `amount_planned` (previsto), `amount` (realizado)
  - Datas: `competence_date`, `due_date`, `payment_date`
  - `status` (planned/paid/overdue/canceled)
  - Vínculos: `account_id`, `card_id`, `invoice_id`, `category_id`, `subcategory_id`, `cost_center`, `responsible_member_id → family_members`. `category_splits JSON` permite ratear um único lançamento entre categorias/subcategorias; a soma das partes é o valor do lançamento e a conciliação continua usando o total.
  - Transferência: `transfer_account_id`, `transfer_group_id` (par débito/crédito)
  - Parcelamento: `installment_group_id`, `installment_number`, `installment_total`
  - Recorrência: `recurrence_id`, `recurrence_rule` (JSON: freq/interval/until)
  - Extras: `tags JSON`, `latitude`, `longitude`, `created_by`, `updated_by` (controle de quem lançou/alterou na família)
- **transaction_attachments** — `transaction_id`, `kind` (receipt/invoice/photo/document), `file_name`, `file_path`, `mime_type`, `size_bytes`, `ocr_data JSON` (valor/data/estabelecimento/itens extraídos), `nfce_key` (QR Code NFC-e)

## Planejamento

- **budgets** — um por mês/escopo: `reference_month DATE`, `scope` (personal/family), `notes`
- **budget_items** — `budget_id`, `category_id`, `subcategory_id` (opcional), `planned_amount`, `is_fixed` (categoria fixa × variável), `due_day` (dia do vencimento, para despesas fixas). Aceita categorias de despesa e de receita (receitas planejadas). Realizado é calculado sobre `transactions`.
- **goals** — `name`, `target_amount`, `target_date`, `accumulated_amount`, `linked_account_id`, `icon`, `color`, `status` (active/done/paused)
- **debts** — `name`, `type` (loan/financing/installment_plan), `institution`, `original_amount`, `outstanding_balance`, `interest_rate_monthly`, `total_installments`, `paid_installments`, `installment_amount`, `first_due_date`, `due_day`, `status` (active/paid_off/renegotiated)
- **investments** — `name`, `type` (fixed_income/stocks/funds/pension/crypto/other), `institution`, `applied_amount`, `current_amount`, `last_quote_date`
- **investment_movements** — histórico de aportes/resgates: `investment_id`, `type` (deposit/withdrawal/yield), `amount`, `movement_date`

## Importação

- **import_batches** — base comum da importação: `source` (csv/ofx/pdf), `file_name`, `file_hash` (SHA-256), `import_kind` (bank_statement/credit_card_invoice), `account_id` (extrato), `card_id`, `invoice_due_date`, `reference_month`, `column_mapping JSON`, `status` (analyzing/reviewing/confirmed/canceled), `total_items`, `imported_items`. Para faturas também guarda `official_total_cents`, `recognized_total_cents`, `current_total_cents`, `projected_total_cents`, `final_difference_cents`, `extracted_metadata JSON`, `reconciliation_status`, `analysis_at` e `completed_at`.
- **import_items** — base comum dos itens: `batch_id`, `raw JSON`, `item_date`, `description`, `amount`, `amount_cents`, `kind`, `fitid`, categoria sugerida, status e transação criada. Na conciliação, `item_origin` distingue `statement`/`hopecash`; `match_type` distingue `exact_match`/`probable_match`/`ambiguous`/`statement_only`/`hopecash_only`; `match_confidence`, `match_reason`, `matched_transaction_id`, `matched_transaction_version` e `candidate_transaction_ids JSON` registram a análise; `decision`, `decision_payload JSON` e `reviewed_at` registram a revisão. Linhas `hopecash` representam transações do ciclo ausentes no arquivo, sem criar uma estrutura concorrente.

Todos os cálculos de conciliação usam centavos inteiros. `amount` decimal permanece por compatibilidade com extratos e transações existentes.

## Plataforma

- **notifications** — caixa de entrada por usuário: `type` (bill_due/bill_overdue/budget_exceeded/low_balance/invoice_closed/goal_late/unusual_expense/duplicate_suspect/sync_failed/…), `title`, `body`, `data JSON`, `read_at`
- **sync_operations** — log de push de sincronização: `operation_id UNIQUE` (idempotência), `user_id`, `device_id`, `entity`, `entity_id`, `op` (create/update/delete), `payload JSON`, `base_version`, `result` (applied/conflict_resolved/rejected), `conflict_payload JSON` (versão perdedora)
- **audit_logs** — `user_id`, `family_id`, `entity`, `entity_id`, `action`, `changes JSON`, `ip`, `user_agent`, `created_at` (append-only, sem soft delete)

## Notificações push (Firebase Cloud Messaging)

Sem colunas de sincronização (não são entidades offline-first do app) — cada tabela tem seu próprio ciclo de vida.

- **push_devices** — um token FCM por linha, único: `user_id`, `token UNIQUE`, `platform` (web/pwa/android/ios), `install_id`, `app_version`, `locale`, `timezone`, `last_used_at`, `is_active`, `revoked_at`, `last_error`, `failed_at`. Um usuário pode ter vários dispositivos; registrar o mesmo token novamente é idempotente (atualiza a linha, inclusive transferindo o dono se o aparelho trocar de conta).
- **push_preferences** — uma linha por usuário (criada com padrão no primeiro acesso): `push_enabled` (chave geral), `due_reminders_enabled`, `financial_insights_enabled`, `tips_enabled`, `email_notifications_enabled` (default `true` — fallback por e-mail quando não há dispositivo push ativo; desligável independente do push), `reminder_advance_days`, `preferred_hour` (0-23, opcional), `timezone`.
- **push_campaigns** — campanhas criadas pela retaguarda: `title`, `body`, `category` (general/tips/insights/maintenance/promo), `audience` (all/selected), `target_user_ids JSON` (quando `selected`), `deep_link` (validado contra a lista de permissão), `status` (draft/scheduled/processing/sent/partially_sent/canceled/failed), `scheduled_at` (UTC), `scheduled_timezone` (só para exibição — o fuso usado na criação), `created_by → retaguarda_users`, `recipients_total`, `success_total`, `failure_total`, `claimed_at`/`claimed_by` (claim otimista do scheduler).
- **push_deliveries** — uma linha por tentativa de entrega (campanha ou mensagem automática): `campaign_id` (null para mensagens automáticas), `source_type` (campaign/due_reminder/financial_insight/tip), `source_id` (ex.: `transactions.id`, só para due_reminder), `reminder_kind` (advance/due_today/overdue, só para due_reminder), `user_id`, `channel` (`push`|`email`, default `push`), `device_id` (nullable — `null` quando `channel = 'email'`, já que a entrega não está atrelada a um token FCM específico), `status` (pending/sending/sent/failed), `provider_message_id`, `attempts`, `error` (sanitizado, nunca o token), `next_attempt_at`, `idempotency_key UNIQUE` (evita duplicidade entre ciclos/instâncias do worker; para e-mail usa sufixo `:email` em vez do `device_id`). Por usuário elegível sem dispositivo ativo (e com `email_notifications_enabled = true`) é criada **uma única** linha com `channel = 'email'`, em vez de uma por dispositivo.
- **push_automation_rules** — uma linha por tipo de mensagem automática (`due_reminder`/`financial_insight`/`tip`), gerenciada pela retaguarda em **Notificações → Mensagens automáticas**: `message_type UNIQUE`, `enabled` (liga/desliga geral do tipo — se desligado, nenhuma mensagem desse tipo sai, mesmo que a preferência do usuário esteja ligada), `frequency_days` (para `due_reminder`: antecedência padrão em dias, usada quando o usuário não tem preferência própria; para `financial_insight`/`tip`: intervalo mínimo entre envios ao mesmo usuário), `title`/`body` (conteúdo enviado — `null` para `due_reminder`, cujo conteúdo varia por `reminder_kind`), `config JSON` (parâmetros extra, ex.: `financial_insight` → `{threshold_percent}`), `updated_by → retaguarda_users`. Sem colunas de sincronização — as três linhas são criadas automaticamente (valores padrão) no primeiro acesso.

## Banco local (Drift/SQLite no app)

Espelha as tabelas de negócio (mesmos ids/colunas, com `sync_status`) e acrescenta:

- **pending_operations** — fila offline: `operation_id`, `entity`, `entity_id`, `op`, `payload JSON`, `base_version`, `created_at`, `attempts`
- **sync_state** — chave/valor: cursor do último pull, device_id, timestamps

## Relacionamentos principais

```
users 1─N user_sessions
users 1─N families (owner) 1─N family_members N─1 users
users 1─N bank_accounts 1─N transactions N─1 categories 1─N subcategories
credit_cards 1─N credit_card_invoices 1─N transactions
budgets 1─N budget_items N─1 categories
investments 1─N investment_movements
import_batches 1─N import_items N─1 transactions
transactions 1─N transaction_attachments
```
