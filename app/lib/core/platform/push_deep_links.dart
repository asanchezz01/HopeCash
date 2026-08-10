/// Lista de permissão de destinos internos que um push pode abrir — espelha
/// `backend/src/modules/push/deepLinks.js`. Defesa em profundidade: o backend
/// já valida antes de enviar, mas o app nunca navega para um link que não
/// reconhece, mesmo que o payload tenha sido adulterado.
const _allowedBasePaths = {
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
};

final _dynamicPathPatterns = [RegExp(r'^/more/credit-cards/[a-zA-Z0-9-]{1,64}$')];
final _queryKeyRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,40}$');
final _queryValueRe = RegExp(r'^[a-zA-Z0-9_-]{0,80}$');

bool _isValidQueryString(String query) {
  if (query.isEmpty) return true;
  for (final pair in query.split('&')) {
    final parts = pair.split('=');
    final key = parts.isNotEmpty ? parts[0] : '';
    final value = parts.length > 1 ? parts[1] : '';
    if (!_queryKeyRe.hasMatch(key) || !_queryValueRe.hasMatch(value)) return false;
  }
  return true;
}

/// Valida um deep link (path [+ query string]) recebido de um push.
bool isAllowedDeepLink(String? rawPath) {
  if (rawPath == null || rawPath.isEmpty || rawPath.length > 200) return false;
  if (!rawPath.startsWith('/')) return false;
  final splitIndex = rawPath.indexOf('?');
  final path = splitIndex == -1 ? rawPath : rawPath.substring(0, splitIndex);
  final query = splitIndex == -1 ? '' : rawPath.substring(splitIndex + 1);
  final pathAllowed = _allowedBasePaths.contains(path) ||
      _dynamicPathPatterns.any((re) => re.hasMatch(path));
  return pathAllowed && _isValidQueryString(query);
}
