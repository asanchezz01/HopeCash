/**
 * Metadados de descoberta OAuth — RFC 8414 (Authorization Server Metadata) e
 * RFC 9728 (Protected Resource Metadata). É assim que hosts MCP (ChatGPT,
 * Claude) descobrem sozinhos onde ficam /authorize, /token e /register a
 * partir da URL do MCP. Montado na raiz do app (fora de /api/v1), sem auth.
 */
import { Router } from 'express';
import { config } from '../../config.js';

const router = Router();

router.get('/oauth-authorization-server', (_req, res) => {
  const issuer = config.publicUrl;
  res.json({
    issuer,
    authorization_endpoint: `${issuer}/api/v1/oauth/authorize`,
    token_endpoint: `${issuer}/api/v1/oauth/token`,
    registration_endpoint: `${issuer}/api/v1/oauth/register`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code'],
    code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['none'],
  });
});

// Caminho derivado do recurso protegido (/api/v1/ai/mcp), como os clientes MCP esperam.
router.get('/oauth-protected-resource/api/v1/ai/mcp', (_req, res) => {
  const issuer = config.publicUrl;
  res.json({
    resource: `${issuer}/api/v1/ai/mcp`,
    authorization_servers: [issuer],
  });
});

export default router;
