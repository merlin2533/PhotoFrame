import bcrypt from 'bcrypt';
import { v4 as uuidv4 } from 'uuid';
import type { DatabaseSync } from 'node:sqlite';
import { getDb } from '../db';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from './jwt';

const BCRYPT_ROUNDS = 12;

export interface User {
  id: string;
  username: string;
  password_hash: string;
  storage_used_bytes: number;
  created_at: string;
}

export class AuthError extends Error {
  constructor(message: string, public statusCode = 401) {
    super(message);
  }
}

// In-memory store of valid refresh-token ids (jti) per user, backed by a
// lightweight table so tokens survive restarts and can be revoked.
function ensureRefreshTable(db: DatabaseSync) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS refresh_tokens (
      jti TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      revoked_at TEXT
    );
  `);
}

export function registerUser(username: string, password: string): User {
  const db = getDb();
  ensureRefreshTable(db);

  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (existing) {
    throw new AuthError('username already taken', 409);
  }

  const id = uuidv4();
  const passwordHash = bcrypt.hashSync(password, BCRYPT_ROUNDS);

  db.prepare(
    'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
  ).run(id, username, passwordHash);

  return db.prepare('SELECT * FROM users WHERE id = ?').get(id) as unknown as User;
}

export function verifyPassword(username: string, password: string): User {
  const db = getDb();
  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username) as User | undefined;
  if (!user) throw new AuthError('invalid credentials', 401);

  const ok = bcrypt.compareSync(password, user.password_hash);
  if (!ok) throw new AuthError('invalid credentials', 401);

  return user;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export function issueTokenPair(userId: string): TokenPair {
  const db = getDb();
  ensureRefreshTable(db);

  const jti = uuidv4();
  db.prepare('INSERT INTO refresh_tokens (jti, user_id) VALUES (?, ?)').run(jti, userId);

  return {
    accessToken: signAccessToken(userId),
    refreshToken: signRefreshToken(userId, jti),
  };
}

export function refreshTokenPair(refreshToken: string): TokenPair {
  const db = getDb();
  ensureRefreshTable(db);

  let payload;
  try {
    payload = verifyRefreshToken(refreshToken);
  } catch {
    throw new AuthError('invalid refresh token', 401);
  }

  const row = db
    .prepare('SELECT * FROM refresh_tokens WHERE jti = ?')
    .get(payload.jti) as { jti: string; user_id: string; revoked_at: string | null } | undefined;

  if (!row || row.revoked_at) {
    throw new AuthError('refresh token revoked or unknown', 401);
  }

  // Rotate: revoke old, issue new.
  db.prepare('UPDATE refresh_tokens SET revoked_at = strftime(\'%Y-%m-%dT%H:%M:%fZ\', \'now\') WHERE jti = ?').run(
    payload.jti,
  );

  return issueTokenPair(row.user_id);
}

export function revokeRefreshToken(jti: string): void {
  const db = getDb();
  ensureRefreshTable(db);
  db.prepare('UPDATE refresh_tokens SET revoked_at = strftime(\'%Y-%m-%dT%H:%M:%fZ\', \'now\') WHERE jti = ?').run(jti);
}

export function getUserById(id: string): User | undefined {
  const db = getDb();
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id) as User | undefined;
}
