import type { CorsOptions } from 'cors';
import { env } from './env';

const LOCALHOST_ORIGIN = /^https?:\/\/localhost(:\d+)?$/;

/**
 * Origin policy shared by the HTTP API and Socket.IO.
 *
 * - CORS_ORIGINS set: exactly those origins.
 * - otherwise, outside production: any http(s)://localhost origin, so local
 *   web clients keep working during development.
 * - otherwise: no cross-origin browser access. The native apps do not use
 *   CORS, and the admin panel is served from the same origin.
 */
export function corsOrigin(): NonNullable<CorsOptions['origin']> {
  const configured = env.CORS_ORIGINS.split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);

  if (configured.length > 0) return configured;
  if (env.NODE_ENV !== 'production') return LOCALHOST_ORIGIN;
  return false;
}
