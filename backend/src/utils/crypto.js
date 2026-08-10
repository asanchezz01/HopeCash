import crypto from 'node:crypto';

/** Gera hash SHA-256 de uma string. */
export function sha256(input) {
  return crypto.createHash('sha256').update(input, 'utf8').digest('hex');
}
