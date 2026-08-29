import { Router } from 'express';
import pkg from '../../package.json';
import { getDb } from '../db';

export const healthRouter = Router();

healthRouter.get('/healthz', (_req, res) => {
  try {
    getDb().prepare('SELECT 1').get();
    res.status(200).json({ status: 'ok' });
  } catch (err) {
    res.status(503).json({ status: 'error', message: (err as Error).message });
  }
});

healthRouter.get('/version', (_req, res) => {
  res.json({ name: pkg.name, version: pkg.version });
});
