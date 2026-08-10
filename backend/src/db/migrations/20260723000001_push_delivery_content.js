/**
 * Congela o conteúdo de notificações geradas no momento do enfileiramento.
 * Dicas personalizadas por IA precisam manter o mesmo título/corpo em todos
 * os dispositivos, no e-mail e em eventuais retentativas.
 */
export async function up(knex) {
  await knex.schema.alterTable('push_deliveries', (t) => {
    t.text('notification_content');
  });
}

export async function down(knex) {
  await knex.schema.alterTable('push_deliveries', (t) => {
    t.dropColumn('notification_content');
  });
}
