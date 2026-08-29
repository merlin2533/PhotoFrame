import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';

export interface AdminTokenPayload {
  role: 'admin';
  username: string;
}

function timingSafeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) {
    // Still run a comparison of equal length to avoid leaking length via timing.
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

export function verifyAdminCredentials(username: string, password: string): boolean {
  return timingSafeEqual(username, env.ADMIN_USERNAME) && timingSafeEqual(password, env.ADMIN_PASSWORD);
}

export function signAdminToken(): string {
  const payload: AdminTokenPayload = { role: 'admin', username: env.ADMIN_USERNAME };
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: '12h' });
}

export function verifyAdminToken(token: string): AdminTokenPayload {
  const decoded = jwt.verify(token, env.JWT_SECRET) as AdminTokenPayload;
  if (decoded.role !== 'admin') throw new Error('not an admin token');
  return decoded;
}
