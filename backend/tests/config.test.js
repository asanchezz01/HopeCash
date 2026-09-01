import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

async function freshConfig() {
  const { config } = await import('../src/config.js');
  return config;
}

beforeEach(() => {
  vi.resetModules();
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

describe('Configuração da Cerebras', () => {
  it('lê a API key diretamente do ambiente e remove espaços externos', async () => {
    vi.stubEnv('CEREBRAS_API_KEY', '  cerebras-direta  ');

    const config = await freshConfig();
    const cerebras = config.llm.providers.find((provider) => provider.id === 'cerebras');

    expect(cerebras.apiKey).toBe('cerebras-direta');
  });

  it('ignora o antigo ponteiro CEREBRAS_API_KEY_FILE', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hopecash-cerebras-'));
    const legacyKeyFile = path.join(tempDir, 'cerebras_api.txt');
    fs.writeFileSync(legacyKeyFile, 'chave-legada', 'utf8');
    vi.stubEnv('NODE_ENV', 'development');
    vi.stubEnv('CEREBRAS_API_KEY', '');
    vi.stubEnv('CEREBRAS_API_KEY_FILE', legacyKeyFile);

    try {
      const config = await freshConfig();
      const cerebras = config.llm.providers.find((provider) => provider.id === 'cerebras');

      expect(cerebras.apiKey).toBe('');
    } finally {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });
});
