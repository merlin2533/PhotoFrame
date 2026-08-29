import { Router } from 'express';
import { z } from 'zod';
import { env } from '../config/env';
import {
  AuthError,
  issueTokenPair,
  refreshTokenPair,
  registerUser,
  verifyPassword,
} from '../auth/userAuth';
import { authRateLimiter } from '../middleware/rateLimit';
import { isRegistrationEnabled } from './admin';

export const authRouter = Router();

authRouter.use(authRateLimiter);

const registerSchema = z.object({
  username: z.string().min(3).max(64),
  password: z.string().min(8).max(256),
  inviteCode: z.string().optional(),
});

authRouter.post('/register', (req, res) => {
  const parsed = registerSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request', details: parsed.error.flatten() });
    return;
  }

  if (!isRegistrationEnabled(env.REGISTRATION_ENABLED)) {
    res.status(403).json({ error: 'registration is currently disabled' });
    return;
  }

  if (env.REGISTRATION_INVITE_CODE && parsed.data.inviteCode !== env.REGISTRATION_INVITE_CODE) {
    res.status(403).json({ error: 'invalid invite code' });
    return;
  }

  try {
    const user = registerUser(parsed.data.username, parsed.data.password);
    const tokens = issueTokenPair(user.id);
    res.status(201).json({ userId: user.id, username: user.username, ...tokens });
  } catch (err) {
    if (err instanceof AuthError) {
      res.status(err.statusCode).json({ error: err.message });
      return;
    }
    throw err;
  }
});

const loginSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(1),
});

authRouter.post('/login', (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request' });
    return;
  }

  try {
    const user = verifyPassword(parsed.data.username, parsed.data.password);
    const tokens = issueTokenPair(user.id);
    res.json({ userId: user.id, username: user.username, ...tokens });
  } catch (err) {
    if (err instanceof AuthError) {
      res.status(err.statusCode).json({ error: err.message });
      return;
    }
    throw err;
  }
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

authRouter.post('/refresh', (req, res) => {
  const parsed = refreshSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request' });
    return;
  }

  try {
    const tokens = refreshTokenPair(parsed.data.refreshToken);
    res.json(tokens);
  } catch (err) {
    if (err instanceof AuthError) {
      res.status(err.statusCode).json({ error: err.message });
      return;
    }
    throw err;
  }
});
