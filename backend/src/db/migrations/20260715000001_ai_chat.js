/**
 * Chat com a assistente Hope (Etapa 2 do AI_ROADMAP).
 *
 * Conversas vivem apenas no servidor (o chat depende do provedor LLM, logo só
 * funciona online) — por isso NÃO entram no registro de sincronização.
 * Exclusão é definitiva (hard delete), alinhada à premissa LGPD.
 */

export async function up(knex) {
  await knex.schema.createTable('ai_conversations', (t) => {
    t.uuid('id').primary();
    t.uuid('user_id').notNullable();
    t.string('title', 80).notNullable();
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable();
    t.index(['user_id', 'updated_at']);
  });

  await knex.schema.createTable('ai_messages', (t) => {
    t.uuid('id').primary();
    t.uuid('conversation_id').notNullable();
    t.string('role', 12).notNullable(); // user|assistant
    t.text('content').notNullable();
    // Log das tools executadas para gerar a resposta (auditoria/telemetria).
    t.text('tool_calls', 'mediumtext');
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.index(['conversation_id', 'created_at']);
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('ai_messages');
  await knex.schema.dropTableIfExists('ai_conversations');
}
