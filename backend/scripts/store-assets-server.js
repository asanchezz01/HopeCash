/**
 * Servidor local efemero para capturas da App Store.
 *
 * Usa o banco SQLite em memoria do ambiente de testes, aplica migrations e
 * carrega o usuario demo. Nenhum dado de producao e lido ou alterado.
 */
process.env.NODE_ENV = 'test';
process.env.PORT ??= '3000';
process.env.CORS_ALLOWED_ORIGINS = [8090, 8091]
  .flatMap((port) => [
    `http://127.0.0.1:${port}`,
    `http://localhost:${port}`,
  ])
  .join(',');

const [{ db }, { createApp }] = await Promise.all([
  import('../src/db/knex.js'),
  import('../src/app.js'),
]);

await db.migrate.latest();
await db.seed.run();
await db('users')
  .where({ email: 'demo@hopecash.app' })
  .update({ onboarding_completed_at: new Date().toISOString() });

const app = createApp();
const port = Number(process.env.PORT);
const server = app.listen(port, () => {
  console.log(`HopeCash capture API ready at http://localhost:${port}`);
});

async function shutdown() {
  server.close(async () => {
    await db.destroy();
    process.exit(0);
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
