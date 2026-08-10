export class HttpError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export const notFound = (msg = 'Registro não encontrado') => new HttpError(404, 'NOT_FOUND', msg);
export const forbidden = (msg = 'Acesso negado') => new HttpError(403, 'FORBIDDEN', msg);
export const unauthorized = (msg = 'Não autenticado') => new HttpError(401, 'UNAUTHORIZED', msg);
export const badRequest = (msg, details) => new HttpError(400, 'BAD_REQUEST', msg, details);
export const conflict = (msg, details) => new HttpError(409, 'VERSION_CONFLICT', msg, details);
