import type { Server as HttpServer } from 'node:http';
import { Server, type Socket } from 'socket.io';
import { verifyDeviceToken } from '../auth/deviceTokens';
import { getDb } from '../db';

let io: Server | null = null;

export function getIo(): Server | null {
  return io;
}

interface AuthedSocket extends Socket {
  frameId?: string;
}

/**
 * Initializes Socket.IO on the same HTTP server/port as Express. Auth
 * happens once at handshake via a device token; a socket may then request
 * to join a pairing room, but only after we verify current membership -
 * this is re-checked at join time (not just at handshake) so a frame
 * removed from a pairing mid-connection cannot keep listening in that room.
 */
export function initSocket(httpServer: HttpServer): Server {
  io = new Server(httpServer, {
    cors: { origin: '*' },
  });

  io.use((socket: AuthedSocket, next) => {
    const token = socket.handshake.auth?.token as string | undefined;
    if (!token) {
      next(new Error('missing device token'));
      return;
    }

    const row = verifyDeviceToken(token);
    if (!row) {
      next(new Error('invalid or revoked device token'));
      return;
    }

    socket.frameId = row.frame_id;
    next();
  });

  io.on('connection', (socket: AuthedSocket) => {
    if (socket.frameId) {
      socket.join(`frame:${socket.frameId}`);
    }

    socket.on('join_pairing', (pairingId: string, ack?: (result: { ok: boolean; error?: string }) => void) => {
      if (!socket.frameId || typeof pairingId !== 'string') {
        ack?.({ ok: false, error: 'invalid request' });
        return;
      }

      const db = getDb();
      const member = db
        .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
        .get(pairingId, socket.frameId);

      if (!member) {
        ack?.({ ok: false, error: 'not a member of this pairing' });
        return;
      }

      socket.join(`pairing:${pairingId}`);
      ack?.({ ok: true });
    });

    socket.on('leave_pairing', (pairingId: string) => {
      if (typeof pairingId === 'string') {
        socket.leave(`pairing:${pairingId}`);
      }
    });
  });

  return io;
}
