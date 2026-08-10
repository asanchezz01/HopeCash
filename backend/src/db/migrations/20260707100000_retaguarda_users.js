/**
 * Retaguarda (backoffice) do HopeCash.
 *
 * Usuários da retaguarda são totalmente separados dos usuários do app: vivem
 * em `retaguarda_users`, autenticam por tokens próprios (typ rtg_*) e não têm
 * relação com dados financeiros. Um superusuário é provisionado na
 * inicialização a partir do .env (ver src/core/bootstrap.js).
 */

export async function up(knex) {
  await knex.schema.createTable('retaguarda_users', (t) => {
    t.uuid('id').primary();
    t.string('name', 120).notNullable();
    t.string('email', 190).notNullable().unique();
    t.string('password_hash', 100).notNullable();
    t.string('role', 20).notNullable().defaultTo('admin'); // superuser|admin
    t.string('status', 20).notNullable().defaultTo('active'); // active|blocked
    t.string('password_reset_token', 64);
    t.datetime('password_reset_expires_at', { precision: 3 });
    t.datetime('last_login_at', { precision: 3 });
    t.datetime('created_at', { precision: 3 }).notNullable();
    t.datetime('updated_at', { precision: 3 }).notNullable();
    t.datetime('deleted_at', { precision: 3 });
    t.integer('version').notNullable().defaultTo(1);
  });

  await knex.schema.createTable('retaguarda_sessions', (t) => {
    t.uuid('id').primary();
    t.uuid('retaguarda_user_id').notNullable().index();
    t.string('refresh_token_hash', 64).notNullable();
    t.string('device_name', 120);
    t.string('ip', 45);
    t.string('user_agent', 300);
    t.datetime('expires_at', { precision: 3 }).notNullable();
    t.datetime('revoked_at', { precision: 3 });
    t.datetime('created_at', { precision: 3 }).notNullable();
  });
}

export async function down(knex) {
  await knex.schema.dropTableIfExists('retaguarda_sessions');
  await knex.schema.dropTableIfExists('retaguarda_users');
}
