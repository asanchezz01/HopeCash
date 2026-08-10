import pino from 'pino';
import { config } from './config.js';

export const logger = pino({
  level: config.isTest ? 'silent' : config.logLevel,
  base: { app: 'hopecash-api' },
  // O serializer padrão do pino-http despeja req.headers inteiro, então todo
  // Bearer (JWT do app e PAT de host MCP) estava indo em texto plano para o
  // `docker logs` — qualquer um com acesso ao container podia se autenticar
  // como qualquer usuário. Encontrado em 2026-08-08 investigando as falhas de
  // MCP; a atribuição de requisição→usuário agora é feita pela tabela
  // `mcp_logs`, não por garimpar token no log.
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      'res.headers["set-cookie"]',
    ],
    censor: '[Redacted]',
  },
});
