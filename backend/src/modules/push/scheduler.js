import { config } from '../../config.js';
import { logger } from '../../logger.js';
import { processDueScheduledCampaigns } from './services/campaignService.js';
import { processDueReminders } from './services/dueReminderService.js';
import { processFinancialInsights } from './services/financialInsightService.js';
import { processTips } from './services/tipService.js';
import { dispatchPendingDeliveries } from './services/deliveryService.js';

let timer = null;
let running = false;

/**
 * Um ciclo completo: reivindica campanhas agendadas cuja hora chegou,
 * enfileira as mensagens automáticas devidas hoje (avisos de vencimento,
 * insights financeiros, dicas — cada uma só roda se a regra correspondente
 * estiver habilitada na retaguarda) e despacha (com retry) tudo o que
 * estiver pendente. Idempotente e seguro para rodar em várias instâncias ao
 * mesmo tempo — a segurança vem do claim otimista em cada tabela, não de um
 * lock global.
 */
async function tick() {
  if (running) return; // um ciclo anterior ainda não terminou — não sobrepõe
  running = true;
  try {
    await processDueScheduledCampaigns();
    await processDueReminders();
    await processFinancialInsights();
    await processTips();
    await dispatchPendingDeliveries();
  } catch (err) {
    logger.error({ err: err.message }, 'Falha no ciclo do scheduler de push');
  } finally {
    running = false;
  }
}

export function startPushScheduler() {
  if (timer || !config.push.schedulerEnabled) return;
  timer = setInterval(tick, config.push.schedulerIntervalMs);
  timer.unref?.();
  logger.info({ intervalMs: config.push.schedulerIntervalMs }, 'Scheduler de push iniciado');
}

export function stopPushScheduler() {
  if (timer) clearInterval(timer);
  timer = null;
}

/** Executa um ciclo manualmente, sem depender do setInterval — usado pelos testes. */
export async function runPushSchedulerTick() {
  await tick();
}
