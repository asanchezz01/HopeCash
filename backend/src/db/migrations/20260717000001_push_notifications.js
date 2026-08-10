/**
 * Notificações push (Firebase Cloud Messaging): dispositivos, preferências,
 * campanhas da retaguarda e o registro de tentativas de entrega.
 *
 * A tabela `notifications` (caixa de entrada por usuário) já existe desde o
 * schema inicial e não é tocada aqui — dispositivos/campanhas/entregas são
 * conceitos separados (quem pode receber push, o que foi disparado, e o
 * resultado de cada tentativa de envio).
 */
export async function up(knex) {
  await knex.schema.createTable('push_devices', (t) => {
    t.uuid('id').primary();
    t.uuid('user_id').notNullable().index();
    t.string('token', 500).notNullable().unique();
    t.string('platform', 10).notNullable(); // web|pwa|android|ios
    t.string('install_id', 120);
    t.string('app_version', 30);
    t.string('locale', 10);
    t.string('timezone', 60);
    t.datetime('last_used_at', { precision: 3 });
    t.boolean('is_active').notNullable().defaultTo(true);
    t.datetime('revoked_at', { precision: 3 });
    t.string('last_error', 255);
    t.datetime('failed_at', { precision: 3 });
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable().index();
  });

  await knex.schema.createTable('push_preferences', (t) => {
    t.uuid('id').primary();
    t.uuid('user_id').notNullable().unique();
    t.boolean('push_enabled').notNullable().defaultTo(true);
    t.boolean('due_reminders_enabled').notNullable().defaultTo(true);
    t.boolean('financial_insights_enabled').notNullable().defaultTo(true);
    t.boolean('tips_enabled').notNullable().defaultTo(true);
    t.integer('reminder_advance_days').notNullable().defaultTo(3);
    t.integer('preferred_hour'); // 0-23, horário preferencial de envio
    t.string('timezone', 60).notNullable().defaultTo('America/Sao_Paulo');
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable();
  });

  await knex.schema.createTable('push_campaigns', (t) => {
    t.uuid('id').primary();
    t.string('title', 150).notNullable();
    t.string('body', 500).notNullable();
    t.string('category', 30).notNullable().defaultTo('general'); // general|tips|insights|maintenance|promo
    t.string('audience', 20).notNullable().defaultTo('all'); // all|selected
    t.text('target_user_ids'); // JSON array de ids (audience = selected)
    t.string('deep_link', 300);
    t.string('status', 20).notNullable().defaultTo('draft').index();
    // draft|scheduled|processing|sent|partially_sent|canceled|failed
    t.datetime('scheduled_at', { precision: 3 }).index();
    t.string('scheduled_timezone', 60); // fuso usado na criação, só para exibição
    t.uuid('created_by').notNullable(); // retaguarda_users.id
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable();
    t.datetime('sent_at', { precision: 3 });
    t.datetime('canceled_at', { precision: 3 });
    t.integer('recipients_total').notNullable().defaultTo(0);
    t.integer('success_total').notNullable().defaultTo(0);
    t.integer('failure_total').notNullable().defaultTo(0);
    // Claim otimista do worker: só quem consegue este UPDATE processa a campanha.
    t.datetime('claimed_at', { precision: 3 });
    t.string('claimed_by', 100);
  });

  await knex.schema.createTable('push_deliveries', (t) => {
    t.uuid('id').primary();
    t.uuid('campaign_id').index(); // null para avisos automáticos (due_reminder)
    t.string('source_type', 20).notNullable(); // campaign|due_reminder
    t.uuid('source_id').index(); // ex.: transactions.id para avisos de vencimento
    t.string('reminder_kind', 20); // advance|due_today|overdue (só para due_reminder)
    t.uuid('user_id').notNullable().index();
    t.uuid('device_id').notNullable().index();
    t.string('status', 20).notNullable().defaultTo('pending').index(); // pending|sent|failed
    t.string('provider_message_id', 200);
    t.integer('attempts').notNullable().defaultTo(0);
    t.string('error', 300); // mensagem sanitizada — nunca o token completo
    t.datetime('next_attempt_at', { precision: 3 }).index();
    // Garante que a mesma campanha/aviso nunca seja duplicado(a) para o mesmo dispositivo.
    t.string('idempotency_key', 190).notNullable().unique();
    t.datetime('sent_at', { precision: 3 });
    t.datetime('processed_at', { precision: 3 });
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable();
  });
}

export async function down(knex) {
  const tables = ['push_deliveries', 'push_campaigns', 'push_preferences', 'push_devices'];
  for (const table of tables) await knex.schema.dropTableIfExists(table);
}
