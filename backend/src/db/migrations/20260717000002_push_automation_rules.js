/**
 * Regras de automação das mensagens push do sistema (não confundir com
 * `push_campaigns`, que são mensagens compostas manualmente pela retaguarda).
 * Uma linha por tipo (`message_type`): avisos de vencimento, insights
 * financeiros e dicas da Hope. A retaguarda liga/desliga cada tipo e ajusta a
 * frequência de envio sem precisar de redeploy.
 */
export async function up(knex) {
  await knex.schema.createTable('push_automation_rules', (t) => {
    t.uuid('id').primary();
    t.string('message_type', 30).notNullable().unique(); // due_reminder|financial_insight|tip
    t.boolean('enabled').notNullable().defaultTo(true);
    // due_reminder: antecedência em dias antes do vencimento.
    // financial_insight/tip: intervalo mínimo (dias) entre envios ao mesmo usuário.
    t.integer('frequency_days').notNullable();
    t.string('title', 150); // null para due_reminder (conteúdo já varia por kind: advance/due_today/overdue)
    t.string('body', 500);
    t.text('config'); // JSON extra por tipo (ex.: financial_insight: {threshold_percent})
    t.uuid('updated_by'); // retaguarda_users.id
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable();
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('push_automation_rules');
}
