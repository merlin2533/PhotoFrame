import http from 'node:http';
import path from 'node:path';
import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import helmet from 'helmet';
import { env } from './config/env';
import { corsOrigin } from './config/cors';
import { closeDb, getDb } from './db';
import { ensureStorageDirs } from './storage/contentAddressedStore';
import { getIo, initSocket } from './realtime/socket';
import { startMaintenanceJobs } from './maintenance';

import { authRouter } from './routes/auth';
import { framesRouter } from './routes/frames';
import { pairingRouter } from './routes/pairing';
import { imagesRouter } from './routes/images';
import { configPushRouter } from './routes/configPush';
import { accountRouter } from './routes/account';
import { adminRouter } from './routes/admin';
import { healthRouter } from './routes/health';
import { reportsRouter } from './routes/reports';
import { enforceMaxUploadSize } from './middleware/quota';

function createApp() {
  const app = express();

  // Only trust X-Forwarded-For when explicitly configured for a reverse
  // proxy deployment - see the TRUST_PROXY comment in config/env.ts.
  if (env.TRUST_PROXY) {
    app.set('trust proxy', 1);
  }

  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(cors({ origin: corsOrigin() }));
  app.use(express.json({ limit: '1mb' }));
  app.use(enforceMaxUploadSize);

  // Health/version are unauthenticated and unprefixed for simple LB probes.
  app.use('/', healthRouter);

  const api = express.Router();
  api.use('/auth', authRouter);
  api.use('/frames', framesRouter);
  api.use('/pairing', pairingRouter);
  api.use('/images', imagesRouter);
  api.use('/config-push', configPushRouter);
  api.use('/account', accountRouter);
  api.use('/admin', adminRouter);
  api.use('/reports', reportsRouter);
  app.use('/api/v1', api);

  app.use('/admin', express.static(path.join(__dirname, '..', 'public', 'admin')));

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
    console.error(err);
    if (err.message === 'unsupported file type') {
      res.status(415).json({ error: err.message });
      return;
    }
    res.status(500).json({ error: 'internal server error' });
  });

  return app;
}

function main() {
  ensureStorageDirs();
  getDb(); // triggers migrations

  const app = createApp();
  const server = http.createServer(app);
  initSocket(server);

  server.listen(env.PORT, () => {
    console.log(`PhotoFrame relay server listening on port ${env.PORT} (${env.NODE_ENV})`);
    console.log(`Public URL: ${env.PUBLIC_URL}`);
  });

  const maintenanceTimer = startMaintenanceJobs();

  let shuttingDown = false;
  const shutdown = () => {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log('Shutting down...');
    if (maintenanceTimer) clearInterval(maintenanceTimer);

    // If in-flight requests or keep-alive connections do not finish in time,
    // exit anyway. SQLite's WAL keeps committed data durable regardless.
    setTimeout(() => process.exit(1), 10_000).unref();

    const finish = () => {
      closeDb();
      process.exit(0);
    };
    // io.close() also closes the underlying HTTP server and disconnects all
    // Socket.IO clients. Without a Socket.IO server, close the HTTP server
    // directly.
    const io = getIo();
    if (io) {
      io.close(() => finish());
    } else {
      server.close(() => finish());
    }
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

if (require.main === module) {
  main();
}

export { createApp };
