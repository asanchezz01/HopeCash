/**
 * Clientes OAuth registrados dinamicamente (RFC 7591) — hosts MCP externos
 * (ChatGPT, Claude) que se auto-registram na primeira conexão. Cliente
 * público: sem client_secret, PKCE (S256) é quem garante a segurança da
 * troca do authorization code.
 */
export async function up(knex) {
  if (await knex.schema.hasTable('oauth_clients')) return;

  await knex.schema.createTable('oauth_clients', (t) => {
    t.uuid('id').primary();
    t.string('client_name', 200);
    // Array JSON de redirect_uris permitidos — match exato obrigatório no
    // /authorize e no /token (nunca prefixo/parcial).
    t.text('redirect_uris').notNullable();
    t.timestamps(false, true);
  });
}

export async function down(knex) {
  await knex.schema.dropTable('oauth_clients');
}
