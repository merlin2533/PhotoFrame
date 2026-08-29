import type { NextFunction, Request, Response } from 'express';
import { verifyAccessToken } from '../auth/jwt';
import { verifyDeviceToken } from '../auth/deviceTokens';
import { getDb } from '../db';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      userId?: string;
      frameId?: string;
    }
  }
}

function extractBearerToken(req: Request): string | null {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) return null;
  return header.slice('Bearer '.length).trim();
}

/** Requires a valid user JWT access token (from /auth/login or /auth/refresh). */
export function requireUserAuth(req: Request, res: Response, next: NextFunction): void {
  const token = extractBearerToken(req);
  if (!token) {
    res.status(401).json({ error: 'missing bearer token' });
    return;
  }

  try {
    const payload = verifyAccessToken(token);
    req.userId = payload.sub;
    next();
  } catch {
    res.status(401).json({ error: 'invalid or expired token' });
  }
}

/** Requires a valid device token (issued to a paired frame). */
export function requireDeviceAuth(req: Request, res: Response, next: NextFunction): void {
  const token = extractBearerToken(req);
  if (!token) {
    res.status(401).json({ error: 'missing bearer token' });
    return;
  }

  const row = verifyDeviceToken(token);
  if (!row) {
    res.status(401).json({ error: 'invalid or revoked device token' });
    return;
  }

  req.frameId = row.frame_id;
  next();
}

/**
 * Verifies the authenticated frame (req.frameId, set by requireDeviceAuth)
 * is a member of the pairing named by req.params.pairingId. Must run after
 * requireDeviceAuth.
 */
export function requirePairingMembership(req: Request, res: Response, next: NextFunction): void {
  const pairingId = req.params.pairingId;
  if (!req.frameId) {
    res.status(401).json({ error: 'device authentication required' });
    return;
  }
  if (!pairingId) {
    res.status(400).json({ error: 'missing pairingId' });
    return;
  }

  const db = getDb();
  const member = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(pairingId, req.frameId) as { role: string } | undefined;

  if (!member) {
    res.status(403).json({ error: 'not a member of this pairing' });
    return;
  }

  next();
}
