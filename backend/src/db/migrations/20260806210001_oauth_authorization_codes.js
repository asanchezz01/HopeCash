/**
 * Authorization codes de uso único do fluxo OAuth (RFC 6749 + PKCE, RFC 7636).
 * Mesmo padrão de segredo do PAT: guardamos só o hash SHA-256, nunca o code
 * em claro. `consumed_at` bloqueia replay; `expires_at` é curto (5min) —
 * é só a ponte entre o /authorize e o /token, não o token de acesso final.
 */
export async function up(knex) {
  if (await knex.schema.hasTable('oauth_authorization_codes')) return;

  await knex.schema.createTable('oauth_authorization_codes', (t) => {
    t.uuid('id').primary();
    t.string('code_hash', 64).notNullable().index();
    t.uuid('client_id').notNullable().index();
    t.text('redirect_uri').notNullable();
    t.uuid('user_id').notNullable().index();
    // mcp_read | mcp_write — escolhido pelo usuário na tela de consentimento.
    t.string('kind', 20).notNullable();
    t.string('code_challenge', 128).notNullable();
    t.string('code_challenge_method', 10).notNullable().defaultTo('S256');
    t.text('resource');
    t.datetime('expires_at', { precision: 3 }).notNullable();
    t.datetime('consumed_at', { precision: 3 });
    t.datetime('created_at', { precision: 3 }).notNullable();
  });
}

export async function down(knex) {
  await knex.schema.dropTable('oauth_authorization_codes');
}
