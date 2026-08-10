/**
 * Ações propostas pela Hope (Etapa 3): escrita em duas fases.
 * Não entram no sync; somente o resultado confirmado gera entidades de negócio
 * sincronizáveis e auditadas pelo syncRepo.
 */
export async function up(knex) {
  await knex.schema.createTable('ai_actions', (t) => {
    t.uuid('id').primary();
    t.uuid('user_id').notNullable().index();
    t.uuid('actor_id');
    t.uuid('conversation_id').notNullable().index();
    t.uuid('message_id').index();
    t.string('tool_name', 60).notNullable();
    t.text('payload', 'mediumtext').notNullable();
    t.text('summary').notNullable();
    t.string('status', 20).notNullable().defaultTo('proposed').index();
    t.text('result', 'mediumtext');
    t.text('error');
    t.datetime('expires_at', { precision: 3 }).notNullable().index();
    t.datetime('decided_at', { precision: 3 });
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable();
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('ai_actions');
}
