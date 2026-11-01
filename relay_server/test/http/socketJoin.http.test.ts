import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('socket-join-http');

/**
 * Socket.IO join tests over a real listening server. socket.io-client is not a
 * dependency, so this drives the Engine.IO / Socket.IO v4 wire protocol directly
 * over Node's built-in WebSocket (Node 22+).
 */

let getDb: typeof import('../../src/db').getDb;
let createApp: typeof import('../../src/index').createApp;
let initSocket: typeof import('../../src/realtime/socket').initSocket;
let getIo: typeof import('../../src/realtime/socket').getIo;
let evictFrameFromPairing: typeof import('../../src/realtime/socket').evictFrameFromPairing;
let issueDeviceToken: typeof import('../../src/auth/deviceTokens').issueDeviceToken;

let server: http.Server;
let port: number;

before(async () => {
  ({ getDb } = await import('../../src/db'));
  ({ createApp } = await import('../../src/index'));
  ({ initSocket, getIo, evictFrameFromPairing } = await import('../../src/realtime/socket'));
  ({ issueDeviceToken } = await import('../../src/auth/deviceTokens'));

  server = http.createServer(createApp());
  initSocket(server);
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', () => resolve()));
  port = (server.address() as AddressInfo).port;
});

after(async () => {
  await new Promise<void>((resolve) => {
    const io = getIo();
    if (io) io.close(() => resolve());
    else server.close(() => resolve());
  });
});

function makeFrame(): { frameId: string; token: string } {
  const db = getDb();
  const userId = uuidv4();
  db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(
    userId,
    `user-${userId}`,
    'hash',
  );
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(frameId, userId, 'Frame');
  return { frameId, token: issueDeviceToken(frameId).rawToken };
}

function makePairing(memberFrameIds: string[]): string {
  const db = getDb();
  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Socket pairing');
  memberFrameIds.forEach((frameId, index) => {
    db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
      pairingId,
      frameId,
      index === 0 ? 'owner' : 'member',
    );
  });
  return pairingId;
}

interface TestSocket {
  ws: WebSocket;
  connected: Promise<void>;
  rejected: Promise<string>;
  ack(event: string, ...args: unknown[]): Promise<any>;
  close(): void;
}

/** Opens a Socket.IO connection to the default namespace with the given device token. */
function connect(token: string): TestSocket {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/socket.io/?EIO=4&transport=websocket`);
  let nextAckId = 0;
  const pendingAcks = new Map<number, (value: any) => void>();

  let resolveConnected!: () => void;
  let resolveRejected!: (message: string) => void;
  const connected = new Promise<void>((r) => (resolveConnected = r));
  const rejected = new Promise<string>((r) => (resolveRejected = r));

  ws.addEventListener('message', (event) => {
    const msg = String(event.data);
    if (msg === '2') {
      ws.send('3'); // engine.io ping
    } else if (msg.startsWith('0')) {
      ws.send(`40${JSON.stringify({ token })}`); // Socket.IO CONNECT with auth
    } else if (msg.startsWith('40')) {
      resolveConnected();
    } else if (msg.startsWith('44')) {
      const payload = JSON.parse(msg.slice(2));
      resolveRejected(payload.message);
    } else if (msg.startsWith('43')) {
      const match = /^43(\d+)(.*)$/.exec(msg);
      if (match) {
        const resolve = pendingAcks.get(Number(match[1]));
        pendingAcks.delete(Number(match[1]));
        resolve?.(JSON.parse(match[2])[0]);
      }
    }
  });

  return {
    ws,
    connected,
    rejected,
    ack(event: string, ...args: unknown[]) {
      const id = nextAckId++;
      return new Promise((resolve) => {
        pendingAcks.set(id, resolve);
        ws.send(`42${id}${JSON.stringify([event, ...args])}`);
      });
    },
    close() {
      ws.close();
    },
  };
}

test('a socket with a valid device token connects, and a rejected token is refused by the handshake', async () => {
  const frame = makeFrame();
  const good = connect(frame.token);
  await good.connected;
  good.close();

  const bad = connect('not-a-real-token');
  const message = await bad.rejected;
  assert.match(message, /invalid or revoked device token/);
  bad.close();
});

test('join_pairing succeeds for a member and is refused for a non-member', async () => {
  const member = makeFrame();
  const outsider = makeFrame();
  const pairingId = makePairing([member.frameId]);

  const memberSocket = connect(member.token);
  await memberSocket.connected;
  const ok = await memberSocket.ack('join_pairing', pairingId);
  assert.equal(ok.ok, true);

  const outsiderSocket = connect(outsider.token);
  await outsiderSocket.connected;
  const refused = await outsiderSocket.ack('join_pairing', pairingId);
  assert.equal(refused.ok, false);
  assert.equal(refused.error, 'not a member of this pairing');

  memberSocket.close();
  outsiderSocket.close();
});

test('join_pairing is rate limited per socket (21st request in a minute is refused)', async () => {
  const frame = makeFrame();
  const pairingId = makePairing([frame.frameId]);
  const socket = connect(frame.token);
  await socket.connected;

  let lastResult: any = null;
  for (let i = 0; i < 21; i++) {
    lastResult = await socket.ack('join_pairing', pairingId);
  }
  assert.equal(lastResult.ok, false);
  assert.equal(lastResult.error, 'too many join requests');

  socket.close();
});

test('evicting a frame removes its sockets from the pairing room', async () => {
  const frame = makeFrame();
  const pairingId = makePairing([frame.frameId]);
  const socket = connect(frame.token);
  await socket.connected;
  await socket.ack('join_pairing', pairingId);

  const io = getIo()!;
  const roomSize = async () => (await io.in(`pairing:${pairingId}`).fetchSockets()).length;
  assert.equal(await roomSize(), 1);

  evictFrameFromPairing(frame.frameId, pairingId);
  // socketsLeave is applied on the server; give the event loop one turn.
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(await roomSize(), 0);

  socket.close();
});
