/**
 * Referências a lançamentos citados numa resposta da Hope (ex.: "despesas de
 * hoje"), para o app oferecer um link "Ver lançamento" — inclusive ao
 * recarregar o histórico da conversa.
 */
export async function up(knex) {
  await knex.schema.alterTable('ai_messages', (t) => {
    t.text('references');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('ai_messages', (t) => {
    t.dropColumn('references');
  });
}
