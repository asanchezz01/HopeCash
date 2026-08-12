import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import pinoHttp from 'pino-http';
import swaggerUi from 'swagger-ui-express';
import YAML from 'yaml';

import { config } from './config.js';
import { logger } from './logger.js';
import { authenticate, delegationGuard } from './middleware/auth_pat.js';
import { errorHandler } from './middleware/errorHandler.js';
import { crudRouter } from './core/crudRouter.js';
import { forbidden } from './utils/httpError.js';

// Versao semantica do backend, lida do package.json (fonte unica).
const pkgVersion = (() => {
  try {
    const pkgPath = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'package.json');
    return JSON.parse(fs.readFileSync(pkgPath, 'utf-8')).version || '0.0.0';
  } catch {
    return '0.0.0';
  }
})();

import authRoutes from './modules/auth/auth.routes.js';
import usersRoutes from './modules/users/users.routes.js';
import familiesRoutes from './modules/families/families.routes.js';
import accountsRoutes from './modules/accounts/accounts.routes.js';
import cardsRoutes from './modules/cards/cards.routes.js';
import categoriesRoutes from './modules/categories/categories.routes.js';
import transactionsRoutes from './modules/transactions/transactions.routes.js';
import budgetsRoutes from './modules/budgets/budgets.routes.js';
import cashflowRoutes from './modules/cashflow/cashflow.routes.js';
import dashboardRoutes from './modules/dashboard/dashboard.routes.js';
import importsRoutes from './modules/imports/imports.routes.js';
import investmentsRoutes from './modules/investments/investments.routes.js';
import delegationsRoutes from './modules/delegations/delegations.routes.js';
import syncRoutes from './modules/sync/sync.routes.js';
import aiRoutes from './modules/ai/ai.routes.js';
import retaguardaRoutes from './modules/retaguarda/index.js';
import pushRoutes from './modules/push/push.routes.js';
import patRoutes from './modules/pat/pat.routes.js';
import notificationsInboxRoutes from './modules/push/notificationsInbox.routes.js';
import oauthRoutes from './modules/oauth/oauth.routes.js';
import wellknownRoutes from './modules/oauth/wellknown.routes.js';
import supportRoutes from './modules/support/support.routes.js';

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.use(helmet());
  // /.well-known/*, /api/v1/oauth/* e /api/v1/ai/mcp são a superfície do MCP —
  // hosts de terceiros (ChatGPT, Claude, Grok) chamam via fetch() cross-origin
  // direto do próprio domínio deles (inclusive o botão de "testar conexão" do
  // conector, antes de qualquer OAuth), então precisam de CORS aberto (sem
  // credentials — não usam cookie, a auth é sempre um Bearer explícito que o
  // JS da página teria que já possuir, então abrir CORS aqui não expõe nada
  // que um Bearer roubado já não exporia via curl direto). O resto da API
  // segue restrito à allowlist de sempre.
  const isPublicMcpSurface = (path) => path.startsWith('/.well-known/')
    || path.startsWith('/api/v1/oauth/')
    || path.startsWith('/api/v1/ai/mcp');
  app.use(cors((req, callback) => {
    if (isPublicMcpSurface(req.path)) {
      return callback(null, { origin: true, credentials: false });
    }
    return callback(null, {
      origin: (origin, cb) => {
        if (!origin || config.corsOrigins.length === 0 || config.corsOrigins.includes(origin)) {
          return cb(null, true);
        }
        return cb(new Error('Origem não permitida pelo CORS'));
      },
      credentials: true,
    });
  }));
  app.use(express.json({ limit: '2mb' }));
  // RFC 6749 usa form-encoded no /token; o formulário HTML de login+consentimento
  // do OAuth também posta assim (sem JS — ver modules/oauth/pages.js).
  app.use(express.urlencoded({ extended: false }));
  if (!config.isTest) app.use(pinoHttp({ logger, autoLogging: { ignore: (req) => req.url.includes('/health') } }));

  if (!config.isTest) {
    app.use('/api/', rateLimit({ windowMs: 15 * 60_000, limit: 300, standardHeaders: true }));
    app.use('/api/v1/auth', rateLimit({ windowMs: 15 * 60_000, limit: 20, standardHeaders: true }));
    app.use('/api/v1/retaguarda/auth', rateLimit({ windowMs: 15 * 60_000, limit: 20, standardHeaders: true }));
    // OAuth do MCP: /authorize checa senha, /token troca code. Limite mais
    // folgado que o /auth normal de propósito — uma única tentativa de
    // conectar um host (ChatGPT, Grok) já gasta várias chamadas (register +
    // GET /authorize + POST /authorize + /token), e um usuário errando a
    // senha algumas vezes esgotava o limite rápido demais (caso real: filha
    // do Anderson travada em "Too many requests" tentando conectar o
    // ChatGPT). O custo do bcrypt (12 rounds) continua sendo a defesa real
    // contra força bruta aqui, não este limite.
    app.use('/api/v1/oauth', rateLimit({ windowMs: 15 * 60_000, limit: 120, standardHeaders: true }));
    // Chat com IA: cada mensagem custa inferência no Ollama — limite dedicado.
    app.use('/api/v1/ai/chat', rateLimit({ windowMs: 15 * 60_000, limit: 30, standardHeaders: true }));
    app.use('/api/v1/ai/speech', rateLimit({ windowMs: 15 * 60_000, limit: 60, standardHeaders: true }));
  }

  // Metadados de descoberta OAuth (RFC 8414/9728) — raiz do app, sem /api/v1
  // e sem autenticação: é assim que hosts MCP encontram /oauth sozinhos.
  app.use('/.well-known', wellknownRoutes);

  // Swagger UI a partir do contrato OpenAPI.
  const openapiPath = path.join(path.dirname(fileURLToPath(import.meta.url)), 'docs', 'openapi.yaml');
  if (fs.existsSync(openapiPath)) {
    const spec = YAML.parse(fs.readFileSync(openapiPath, 'utf-8'));
    app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(spec));
  }

  const v1 = express.Router();
  v1.get('/health', (_req, res) => res.json({ status: 'ok', version: '1' }));

  // Identidade do build publicado — usada pela retaguarda/app para confirmar
  // qual commit esta efetivamente no ar. Publica (sem autenticacao).
  v1.get('/version', (_req, res) => res.json({
    data: {
      service: 'hopecash-api',
      version: pkgVersion,
      ref: process.env.BUILD_REF || 'local',
      built_at: process.env.BUILD_TIME || null,
    },
  }));
  v1.use('/auth', authRoutes);

  // Formulário público das páginas de suporte/marketing. Protegido por
  // validação, honeypot e rate limit próprio; não exige uma conta no app.
  v1.use('/support', supportRoutes);

  // OAuth do MCP (registro de cliente, /authorize, /token) — deliberadamente
  // público: é assim que se ganha um token, não pode exigir um token antes.
  v1.use('/oauth', oauthRoutes);

  // Retaguarda (backoffice) — autenticação própria, fora do middleware do app.
  v1.use('/retaguarda', retaguardaRoutes);

  // Rotas autenticadas e restritas por tipo de PAT (app).
  v1.use(authenticate);
  v1.use(delegationGuard);
  // Gate de escopo do PAT:
  // - push_transactions → só POST /transactions (nunca escrita arbitrária)
  // - mcp_read/mcp_write → permitido nos caminhos /pat e /ai/mcp/*
  // - outros PATs → bloqueados por padrão
  v1.use((req, _res, next) => {
    if (req.auth?.isPat) {
      const patKind = req.auth.patKind || 'unknown';
      const isMcpToken = ['mcp_read', 'mcp_write'].includes(patKind);

      if (!isMcpToken && !(req.path.startsWith('/transactions') && req.method === 'POST')) {
        throw forbidden('Este token só tem permissão para criar lançamentos');
      }

      // MCP PATs: permitir /pat, /ai/mcp/* e /ai/actions/:id/confirm|reject
      // (confirmação das propostas de escrita em duas fases, feita pelo mesmo
      // host MCP que propôs — mcp_read continua bloqueado por auth.readOnly
      // dentro de confirmAction/rejectAction).
      if (isMcpToken && !req.path.startsWith('/pat') && !req.path.startsWith('/ai/mcp') && !req.path.startsWith('/ai/actions')) {
        throw forbidden('Este token é limitado ao escopo MCP.');
      }
    }
    next();
  });
  v1.use('/users', usersRoutes);
  v1.use('/delegations', delegationsRoutes);
  v1.use('/families', familiesRoutes);
  v1.use('/accounts', accountsRoutes);
  v1.use('/cards', cardsRoutes);
  v1.use('/categories', categoriesRoutes);
  v1.use('/transactions', transactionsRoutes);
  v1.use('/attachments', crudRouter('transaction_attachments', { filterFields: ['transaction_id'] }));
  v1.use('/budgets', budgetsRoutes);
  v1.use('/cashflow', cashflowRoutes);
  v1.use('/dashboard', dashboardRoutes);
  v1.use('/goals', crudRouter('goals', { filterFields: ['status'] }));
  v1.use('/debts', crudRouter('debts', { filterFields: ['status', 'type'] }));
  v1.use('/investments', investmentsRoutes);
  v1.use('/imports', importsRoutes);
  v1.use('/rules/categorization', crudRouter('categorization_rules', { filterFields: ['is_active'] }));
  v1.use('/rules/notification', crudRouter('notification_rules', { filterFields: ['bank_package', 'is_active'] }));
  v1.use('/notifications', notificationsInboxRoutes);
  v1.use('/push', pushRoutes);
  v1.use('/pat', patRoutes);
  v1.use('/sync', syncRoutes);
  v1.use('/ai', aiRoutes);

  app.use('/api/v1', v1);

  app.use((_req, res) => res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Rota não encontrada' } }));
  app.use(errorHandler);
  return app;
}
