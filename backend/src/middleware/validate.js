import { ZodError } from 'zod';
import { HttpError } from '../utils/httpError.js';

/** Valida req[source] com um schema Zod e substitui pelo valor tipado. */
export const validate = (schema, source = 'body') => (req, _res, next) => {
  try {
    const parsed = schema.parse(req[source] ?? {});
    if (source === 'query') {
      // Express 5 expõe req.query como getter; substituímos no próprio objeto.
      Object.defineProperty(req, 'query', { value: parsed, configurable: true, enumerable: true });
    } else {
      req[source] = parsed;
    }
    next();
  } catch (err) {
    if (err instanceof ZodError) {
      throw new HttpError(422, 'VALIDATION_ERROR', 'Dados inválidos', err.issues.map((i) => ({
        path: i.path.join('.'),
        message: i.message,
      })));
    }
    throw err;
  }
};
