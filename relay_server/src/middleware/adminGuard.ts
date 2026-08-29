import type { NextFunction, Request, Response } from 'express';
import { verifyAdminToken } from '../auth/adminAuth';

export function requireAdminAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    res.status(401).json({ error: 'missing admin bearer token' });
    return;
  }

  const token = header.slice('Bearer '.length).trim();
  try {
    verifyAdminToken(token);
    next();
  } catch {
    res.status(401).json({ error: 'invalid or expired admin token' });
  }
}
