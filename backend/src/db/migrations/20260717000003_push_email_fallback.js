/**
 * Fallback por e-mail: quando o usuário não tem nenhum dispositivo push
 * ativo, a mesma mensagem (campanha ou automática) sai por e-mail em vez de
 * ficar sem entrega nenhuma. `channel` marca a via de cada entrega;
 * `device_id` passa a aceitar NULL porque entregas por e-mail não têm
 * dispositivo. `email_notifications_enabled` é o interruptor do usuário
 * para desligar esse fallback.
 */
export async function up(knex) {
  await knex.schema.alterTable('push_deliveries', (t) => {
    t.string('channel', 10).notNullable().defaultTo('push'); // push|email
  });
  await knex.schema.alterTable('push_deliveries', (t) => {
    t.uuid('device_id').nullable().alter();
  });
  await knex.schema.alterTable('push_preferences', (t) => {
    t.boolean('email_notifications_enabled').notNullable().defaultTo(true);
  });
}

export async function down(knex) {
  await knex.schema.alterTable('push_preferences', (t) => {
    t.dropColumn('email_notifications_enabled');
  });
  await knex.schema.alterTable('push_deliveries', (t) => {
    t.dropColumn('channel');
  });
}
