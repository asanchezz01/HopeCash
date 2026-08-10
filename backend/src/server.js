import { createApp } from './app.js';
import { config } from './config.js';
import { logger } from './logger.js';
import { db } from './db/knex.js';
import { ensureSuperuser } from './core/bootstrap.js';
import { startPushScheduler, stopPushScheduler } from './modules/push/scheduler.js';

const app = createApp();

// Provisiona o superusuário da retaguarda (idempotente). Não bloqueia o boot.
ensureSuperuser().catch((err) => logger.error({ err }, 'Falha ao provisionar superusuário'));

// Campanhas agendadas e avisos de vencimento — desligado por padrão (PUSH_SCHEDULER_ENABLED=false).
startPushScheduler();

const server = app.listen(config.port, () => {
  logger.info({ port: config.port, env: config.env }, 'HopeCash API no ar');
});

const shutdown = async (signal) => {
  logger.info({ signal }, 'Encerrando...');
  stopPushScheduler();
  server.close(async () => {
    await db.destroy();
    process.exit(0);
  });
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
