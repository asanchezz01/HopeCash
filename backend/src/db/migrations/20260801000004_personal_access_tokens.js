/**
 * Tabela de Personal Access Tokens (PAT) — Etapa 1 do fluxo de push mobile.
 *
 * Cada token é atrelado ao `user_id` e possui:
 * - `kind`: tipo do token ('push_transactions', 'mcp_read', 'mcp_write').
 * - `scopes`: array de JSON com permissões (gerado automaticamente pelo kind).
 * - `last_used_at`: carimba a última utilização (para expiração silenciosa).
 * - `revoked_at`: permite revogação instantânea sem apagar a linha.
 */
export async function up(knex) {
  // hasTable antes de criar: MySQL faz commit implícito em DDL (CREATE TABLE
  // e os CREATE INDEX que .index() gera não podem ser desfeitos por
  // rollback). Se o processo for interrompido entre esses comandos e o
  // registro em knex_migrations (ex.: deploy que recria o container no meio
  // da migration), a tabela fica órfã e toda tentativa seguinte falha com
  // "already exists" para sempre. `createTableIfNotExists` não resolve —
  // só envolve o CREATE TABLE, não os CREATE INDEX subsequentes — por isso
  // o check explícito, que pula o passo inteiro quando já existe.
  if (await knex.schema.hasTable('personal_access_tokens')) return;

  await knex.schema.createTable('personal_access_tokens', (t) => {
    t.uuid('id').primary();
    t.uuid('user_id').notNullable().index();
    t.string('name', 120).notNullable();
    // Hash SHA-256 do token em clear text — nunca armazenamos o token original.
    t.text('token_hash').notNullable().index();
    // Array de scopes serializado em JSON.stringify/JSON.parse pela aplicação
    // (mesma convenção de tool_calls em ai_messages). MySQL não aceita DEFAULT
    // em colunas BLOB/TEXT/JSON, e o valor é sempre fornecido por createPat().
    t.text('scopes').notNullable();
    // Tipo do token — define automaticamente os scopes.
    t.string('kind').notNullable().defaultTo('push_transactions');
    t.timestamp('expires_at').nullable();
    t.timestamp('last_used_at').nullable();
    t.timestamp('revoked_at').nullable();
    t.timestamps(false, true);
  });
}

export async function down(knex) {
  await knex.schema.dropTable('personal_access_tokens');
}
