import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import { makeApp } from './helpers.js';
import { _setSupportMailerForTests } from '../src/modules/support/support.routes.js';

let api;
const sent = [];

beforeAll(async () => {
  api = await makeApp();
  _setSupportMailerForTests(async (message) => {
    sent.push(message);
    return { sent: true };
  });
});

afterAll(() => {
  _setSupportMailerForTests(null);
});

beforeEach(() => {
  sent.length = 0;
});

describe('Suporte público', () => {
  it('envia uma solicitação válida sem exigir autenticação', async () => {
    const response = await api.post('/api/v1/support').send({
      name: 'Ana Teste',
      email: 'ANA@EXEMPLO.COM',
      category: 'sync',
      app_version: '1.0.0',
      platform: 'ios',
      message: 'Meus lançamentos continuam pendentes depois de reconectar o aparelho.',
      website: '',
    });

    expect(response.status).toBe(201);
    expect(response.body.data.message).toContain('Solicitação enviada');
    expect(sent).toHaveLength(1);
    expect(sent[0].replyTo).toBe('ana@exemplo.com');
    expect(sent[0].subject).toContain('Sincronização');
    expect(sent[0].text).toContain('1.0.0');
  });

  it('rejeita dados inválidos com detalhes de validação', async () => {
    const response = await api.post('/api/v1/support').send({
      name: 'A',
      email: 'email-invalido',
      category: 'unknown',
      message: 'curta',
    });

    expect(response.status).toBe(422);
    expect(response.body.error.code).toBe('VALIDATION_ERROR');
    expect(sent).toHaveLength(0);
  });

  it('absorve o honeypot sem enviar e-mail', async () => {
    const response = await api.post('/api/v1/support').send({
      name: 'Robô Visitante',
      email: 'bot@example.com',
      category: 'other',
      message: 'Mensagem automática longa o bastante para passar pela validação.',
      website: 'https://spam.example.com',
    });

    expect(response.status).toBe(201);
    expect(sent).toHaveLength(0);
  });
});
