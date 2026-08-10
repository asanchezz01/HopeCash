/**
 * Lista de permissão de destinos internos do app (Flutter/GoRouter) que uma
 * notificação push pode abrir. Mantida deliberadamente pequena e alinhada às
 * rotas existentes em `app/lib/app.dart` — nunca aceitamos uma URL arbitrária
 * vinda da retaguarda ou de um payload de push.
 */
const ALLOWED_BASE_PATHS = new Set([
  '/',
  '/transactions',
  '/accounts',
  '/more',
  '/more/credit-cards',
  '/more/budget',
  '/more/goals',
  '/more/debts',
  '/more/investments',
  '/ai-chat',
]);

// Rotas com segmento dinâmico, ex.: /more/credit-cards/:cardId
const DYNAMIC_PATH_PATTERNS = [/^\/more\/credit-cards\/[a-zA-Z0-9-]{1,64}$/];

const QUERY_KEY_RE = /^[a-zA-Z][a-zA-Z0-9_]{0,40}$/;
const QUERY_VALUE_RE = /^[a-zA-Z0-9_-]{0,80}$/;

function isValidQueryString(query) {
  if (!query) return true;
  return query.split('&').every((pair) => {
    const [key, value = ''] = pair.split('=');
    return QUERY_KEY_RE.test(key) && QUERY_VALUE_RE.test(value);
  });
}

/** Valida um deep link (path [+ query string]) contra a lista de permissão. */
export function isAllowedDeepLink(rawPath) {
  if (typeof rawPath !== 'string' || rawPath.length === 0 || rawPath.length > 200) return false;
  if (!rawPath.startsWith('/')) return false;
  const [path, query = ''] = rawPath.split('?');
  const pathAllowed = ALLOWED_BASE_PATHS.has(path) || DYNAMIC_PATH_PATTERNS.some((re) => re.test(path));
  return pathAllowed && isValidQueryString(query);
}

/** Monta e valida um deep link interno (usado pelos avisos automáticos). */
export function buildDeepLink(path, query = {}) {
  const qs = Object.entries(query)
    .filter(([, v]) => v != null)
    .map(([k, v]) => `${k}=${v}`)
    .join('&');
  const link = qs ? `${path}?${qs}` : path;
  if (!isAllowedDeepLink(link)) throw new Error(`Deep link não permitido: ${link}`);
  return link;
}

export const ALLOWED_DEEP_LINKS = Array.from(ALLOWED_BASE_PATHS);
