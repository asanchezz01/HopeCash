import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';

const ROUNDS = 12;

export const hashPassword = (plain) => bcrypt.hash(plain, ROUNDS);
export const verifyPassword = (plain, hash) => bcrypt.compare(plain, hash);

/** Hash rápido (SHA-256) para tokens opacos armazenados no banco (refresh/reset). */
export const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

/**
 * Gera uma senha provisória legível que satisfaz a política do app
 * (>= 8 caracteres, com letras e números). Ex.: "Hope-7K9M2Q".
 * Evita caracteres ambíguos (0/O, 1/I/L).
 */
export function generateTempPassword() {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ';
  const digits = '23456789';
  const pick = (set, n) =>
    Array.from({ length: n }, () => set[crypto.randomInt(set.length)]).join('');
  return `Hope-${pick(alphabet, 3)}${pick(digits, 3)}`;
}
