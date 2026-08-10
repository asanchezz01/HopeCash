import { HttpError } from '../utils/httpError.js';
import { logger } from '../logger.js';

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, _next) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({
      error: { code: err.code, message: err.message, details: err.details },
    });
  }
  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ error: { code: 'BAD_JSON', message: 'JSON malformado' } });
  }
  if (err?.message === 'Origem não permitida pelo CORS') {
    return res.status(403).json({ error: { code: 'CORS_FORBIDDEN', message: err.message } });
  }
  logger.error({ err, url: req.originalUrl }, 'Erro não tratado');
  return res.status(500).json({
    error: { code: 'INTERNAL_ERROR', message: 'Erro interno do servidor' },
  });
}
