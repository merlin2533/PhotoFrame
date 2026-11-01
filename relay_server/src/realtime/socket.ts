import type { Server as HttpServer } from 'node:http';
import { Server, type Socket } from 'socket.io';
import { corsOrigin } from '../config/cors';
import { verifyDeviceToken } from '../auth/deviceTokens';
import { getDb } from '../db';

let io: Server | null = null;

export function getIo(): Server | null {
  return io;
}

interface AuthedSocket extends Socket {
  frameId?: string;
}

// A socket may ask to join pairing rooms at most this many times per window.
// Each join costs a DB lookup, and a legitimate client only joins once per
// pairing it shows, so the limit is generous.
const JOIN_LIMIT_PER_WINDOW = 20;
const JOIN_WINDOW_MS = 60_000;

/**
 * Initializes Socket.IO on the same HTTP server/port as Express. Auth
 * happens once at handshake via a device token; a socket may then request
 * to join a pairing room, but only after we verify current membership.
 *
 * Membership changes are pushed to live sockets by the code that makes them,
 * using the helpers below: a removed member's sockets leave the pairing room,
 * and sockets of a revoked or deleted frame are disconnected. Without that,
 * a frame removed from a pairing would keep receiving album broadcasts until
 * it reconnected.
 */
export function initSocket(httpServer: HttpServer): Server {
  io = new Server(httpServer, {
    cors: { origin: corsOrigin() },
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

    let joinWindowStart = Date.now();
    let joinCount = 0;

    socket.on('join_pairing', (pairingId: string, ack?: (result: { ok: boolean; error?: string }) => void) => {
      const now = Date.now();
      if (now - joinWindowStart >= JOIN_WINDOW_MS) {
        joinWindowStart = now;
        joinCount = 0;
      }
      joinCount += 1;
      if (joinCount > JOIN_LIMIT_PER_WINDOW) {
        ack?.({ ok: false, error: 'too many join requests' });
        return;
      }

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

/**
 * Removes every connected socket of `frameId` from the pairing room. Call
 * when that frame stops being a member (leave, owner removal, admin delete).
 */
export function evictFrameFromPairing(frameId: string, pairingId: string): void {
  io?.in(`frame:${frameId}`).socketsLeave(`pairing:${pairingId}`);
}

/** Removes every connected socket from a pairing room (pairing deleted). */
export function closePairingRoom(pairingId: string): void {
  io?.socketsLeave(`pairing:${pairingId}`);
}

/**
 * Disconnects every connected socket of `frameId`. Call when the frame's
 * device token is revoked or the frame is deleted, so an already-open
 * connection cannot keep using a credential that no longer works.
 */
export function disconnectFrameSockets(frameId: string): void {
  io?.in(`frame:${frameId}`).disconnectSockets(true);
}
