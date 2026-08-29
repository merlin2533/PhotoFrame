import path from 'node:path';
import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const DEFAULT_JWT_SECRETS = new Set([
  '',
  'change-me-to-a-long-random-string-at-least-32-chars',
  'secret',
  'changeme',
]);

const DEFAULT_ADMIN_PASSWORDS = new Set([
  '',
  'change-me-to-a-strong-admin-password',
  'admin',
  'password',
]);

const boolFromString = z
  .string()
  .optional()
  .transform((v) => v === undefined ? undefined : ['1', 'true', 'yes', 'on'].includes(v.toLowerCase()));

const envSchema = z.object({
  PORT: z.coerce.number().int().positive().default(8080),
  PUBLIC_URL: z.string().url().default('http://localhost:8080'),
  DATA_DIR: z.string().default('./data'),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  // Set to true only when the server sits behind a reverse proxy (Traefik/
  // Caddy/Nginx) that sets X-Forwarded-For itself. Enabling it without a
  // trusted proxy in front lets any client spoof its own rate-limit bucket;
  // leaving it disabled behind a real proxy collapses every client onto the
  // proxy's IP and makes express-rate-limit share one bucket for everyone.
  TRUST_PROXY: boolFromString.default('false'),

  JWT_SECRET: z.string().min(1, 'JWT_SECRET is required'),
  JWT_ACCESS_TTL: z.string().default('15m'),
  JWT_REFRESH_TTL: z.string().default('30d'),
  PAIRING_CODE_PEPPER: z.string().optional(),

  ADMIN_USERNAME: z.string().min(1).default('admin'),
  ADMIN_PASSWORD: z.string().min(1, 'ADMIN_PASSWORD is required'),

  REGISTRATION_ENABLED: boolFromString.default('true'),
  REGISTRATION_INVITE_CODE: z.string().optional().default(''),

  MAX_UPLOAD_BYTES: z.coerce.number().int().positive().default(15 * 1024 * 1024),
  MAX_IMAGES_PER_PAIRING: z.coerce.number().int().positive().default(5000),
  MAX_STORAGE_BYTES_PER_USER: z.coerce.number().int().positive().default(5 * 1024 * 1024 * 1024),

  BACKUP_RETENTION_DAYS: z.coerce.number().int().positive().default(14),
});

function parseEnv() {
  const parsed = envSchema.safeParse(process.env);
  if (!parsed.success) {
    console.error('FATAL: invalid environment configuration:');
    console.error(parsed.error.flatten().fieldErrors);
    process.exit(1);
  }

  const data = parsed.data;

  // FAIL-FAST: never allow the server to boot with a default/empty secret.
  if (DEFAULT_JWT_SECRETS.has(data.JWT_SECRET) || data.JWT_SECRET.length < 16) {
    console.error(
      'FATAL: JWT_SECRET is missing, a known default, or too short (min 16 chars). ' +
        'Set a strong random value in your .env file.',
    );
    process.exit(1);
  }

  if (DEFAULT_ADMIN_PASSWORDS.has(data.ADMIN_PASSWORD) || data.ADMIN_PASSWORD.length < 8) {
    console.error(
      'FATAL: ADMIN_PASSWORD is missing, a known default, or too short (min 8 chars). ' +
        'Set a strong admin password in your .env file.',
    );
    process.exit(1);
  }

  return data;
}

const rawEnv = parseEnv();

export const env = {
  ...rawEnv,
  DATA_DIR: path.resolve(rawEnv.DATA_DIR),
  PAIRING_CODE_PEPPER: rawEnv.PAIRING_CODE_PEPPER && rawEnv.PAIRING_CODE_PEPPER.length > 0
    ? rawEnv.PAIRING_CODE_PEPPER
    : `${rawEnv.JWT_SECRET}:pairing-code-pepper`,
};

export const BLOBS_DIR = path.join(env.DATA_DIR, 'blobs');
export const UPLOAD_TMP_DIR = path.join(env.DATA_DIR, 'tmp');
export const BACKUPS_DIR = path.join(env.DATA_DIR, 'backups');
export const DB_PATH = path.join(env.DATA_DIR, 'relay.db');

export type Env = typeof env;
