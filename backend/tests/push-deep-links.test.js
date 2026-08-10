import { describe, it, expect } from 'vitest';
import { isAllowedDeepLink, buildDeepLink } from '../src/modules/push/deepLinks.js';

describe('Push — lista de permissão de deep links', () => {
  it('aceita rotas conhecidas do app', () => {
    expect(isAllowedDeepLink('/')).toBe(true);
    expect(isAllowedDeepLink('/transactions')).toBe(true);
    expect(isAllowedDeepLink('/more/budget')).toBe(true);
    expect(isAllowedDeepLink('/more/credit-cards/abc123-DEF')).toBe(true);
  });

  it('aceita rotas conhecidas com query string simples', () => {
    expect(isAllowedDeepLink('/transactions?openTransactionId=abc-123')).toBe(true);
  });

  it('rejeita rotas fora da lista de permissão', () => {
    expect(isAllowedDeepLink('/admin')).toBe(false);
    expect(isAllowedDeepLink('/more/login-data')).toBe(false);
    expect(isAllowedDeepLink('https://evil.example.com')).toBe(false);
    expect(isAllowedDeepLink('javascript:alert(1)')).toBe(false);
  });

  it('rejeita query string com caracteres perigosos', () => {
    expect(isAllowedDeepLink('/transactions?x=<script>')).toBe(false);
    expect(isAllowedDeepLink('/transactions?x=a"b')).toBe(false);
  });

  it('rejeita entradas malformadas', () => {
    expect(isAllowedDeepLink('')).toBe(false);
    expect(isAllowedDeepLink(null)).toBe(false);
    expect(isAllowedDeepLink(undefined)).toBe(false);
    expect(isAllowedDeepLink('relative/path')).toBe(false);
  });

  it('buildDeepLink monta e valida um link interno', () => {
    const link = buildDeepLink('/transactions', { openTransactionId: 'abc-123' });
    expect(link).toBe('/transactions?openTransactionId=abc-123');
  });

  it('buildDeepLink lança se o path base não é permitido', () => {
    expect(() => buildDeepLink('/nao-existe', { id: '1' })).toThrow();
  });
});
