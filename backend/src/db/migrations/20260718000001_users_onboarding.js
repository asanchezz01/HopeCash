/**
 * Tutorial de boas-vindas visto uma única vez POR USUÁRIO (e não por
 * aparelho): a marca de conclusão passa a viver no servidor, então trocar de
 * dispositivo ou reinstalar o app não reabre o tutorial. NULL = ainda não viu.
 */
export async function up(knex) {
  await knex.schema.alterTable('users', (t) => {
    t.datetime('onboarding_completed_at').nullable();
  });
}

export async function down(knex) {
  await knex.schema.alterTable('users', (t) => {
    t.dropColumn('onboarding_completed_at');
  });
}
