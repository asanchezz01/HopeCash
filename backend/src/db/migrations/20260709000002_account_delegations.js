/**
 * Delegação de acesso entre usuários: o titular (owner) concede a outro
 * usuário (delegate) acesso somente leitura ou total à sua conta.
 * Revogação é soft (revoked_at) para manter histórico/auditoria.
 */
export async function up(knex) {
  await knex.schema.createTable('account_delegations', (t) => {
    t.uuid('id').primary();
    t.uuid('owner_user_id').notNullable().index();
    t.uuid('delegate_user_id').notNullable().index();
    t.string('permission', 10).notNullable().defaultTo('read'); // read|full
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable();
    t.datetime('revoked_at', { precision: 3 });
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('account_delegations');
}
