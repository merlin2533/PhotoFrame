import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { getDb, runInTransaction } from '../db';
import { requireDeviceAuth, requirePairingMembership } from '../middleware/authGuard';
import { generatePairingCode, hashPairingCode } from '../auth/pairingCode';
import { pairingCreateRateLimiter, pairingRedeemRateLimiter } from '../middleware/rateLimit';

export const pairingRouter = Router();

pairingRouter.use(requireDeviceAuth);

const CODE_TTL_MS = 10 * 60 * 1000;
const MAX_REDEEM_ATTEMPTS = 5;

const createCodeSchema = z.object({
  pairingName: z.string().min(1).max(128).optional(),
  pairingId: z.string().optional(), // invite into an existing pairing
});

/** Creates a pairing code. If pairingId is omitted, a new pairing is created with the caller as owner. */
pairingRouter.post('/create-code', pairingCreateRateLimiter, (req, res) => {
  const parsed = createCodeSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request' });
    return;
  }

  const db = getDb();
  let pairingId = parsed.data.pairingId;

  if (pairingId) {
    const membership = db
      .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
      .get(pairingId, req.frameId!);
    if (!membership) {
      res.status(403).json({ error: 'not a member of this pairing' });
      return;
    }
  } else {
    const newPairingId = uuidv4();
    pairingId = newPairingId;
    const name = parsed.data.pairingName ?? 'My PhotoFrame';
    runInTransaction(db, () => {
      db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(newPairingId, name);
      db.prepare(
        'INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)',
      ).run(newPairingId, req.frameId!, 'owner');
    });
  }

  const code = generatePairingCode();
  const codeHash = hashPairingCode(code);
  const expiresAt = new Date(Date.now() + CODE_TTL_MS).toISOString();

  db.prepare(
    'INSERT INTO pairing_codes (code_hash, pairing_id, created_by_frame_id, expires_at) VALUES (?, ?, ?, ?)',
  ).run(codeHash, pairingId, req.frameId!, expiresAt);

  res.status(201).json({ pairingId, code, expiresAt });
});

const redeemSchema = z.object({
  code: z.string().min(4),
});

/** Redeems a pairing code, joining the calling frame to the pairing as a member. */
pairingRouter.post('/redeem', pairingRedeemRateLimiter, (req, res) => {
  const parsed = redeemSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request' });
    return;
  }

  const db = getDb();
  const codeHash = hashPairingCode(parsed.data.code);
  const row = db.prepare('SELECT * FROM pairing_codes WHERE code_hash = ?').get(codeHash) as
    | {
        code_hash: string;
        pairing_id: string;
        expires_at: string;
        consumed_at: string | null;
        attempt_count: number;
      }
    | undefined;

  if (!row) {
    res.status(404).json({ error: 'invalid pairing code' });
    return;
  }

  if (row.consumed_at) {
    res.status(410).json({ error: 'pairing code already used' });
    return;
  }

  if (new Date(row.expires_at).getTime() < Date.now()) {
    res.status(410).json({ error: 'pairing code expired' });
    return;
  }

  if (row.attempt_count >= MAX_REDEEM_ATTEMPTS) {
    res.status(429).json({ error: 'too many attempts for this code' });
    return;
  }

  db.prepare('UPDATE pairing_codes SET attempt_count = attempt_count + 1 WHERE code_hash = ?').run(codeHash);

  runInTransaction(db, () => {
    db.prepare(
      'INSERT OR IGNORE INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)',
    ).run(row.pairing_id, req.frameId!, 'member');
    db.prepare(
      "UPDATE pairing_codes SET consumed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE code_hash = ?",
    ).run(codeHash);
  });

  res.json({ pairingId: row.pairing_id });
});

pairingRouter.get('/:pairingId', requirePairingMembership, (req, res) => {
  const db = getDb();
  const pairing = db.prepare('SELECT * FROM pairings WHERE id = ?').get(req.params.pairingId);
  const members = db
    .prepare('SELECT frame_id, role, joined_at FROM pairing_members WHERE pairing_id = ?')
    .all(req.params.pairingId);
  res.json({ pairing, members });
});

const renameSchema = z.object({
  name: z.string().min(1).max(128),
});

pairingRouter.patch('/:pairingId', requirePairingMembership, (req, res) => {
  const parsed = renameSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request' });
    return;
  }

  const db = getDb();
  db.prepare('UPDATE pairings SET name = ? WHERE id = ?').run(parsed.data.name, req.params.pairingId);
  res.json({ ok: true });
});

/** Removes the calling frame from the pairing. */
pairingRouter.post('/:pairingId/leave', requirePairingMembership, (req, res) => {
  const db = getDb();
  db.prepare('DELETE FROM pairing_members WHERE pairing_id = ? AND frame_id = ?').run(
    req.params.pairingId,
    req.frameId!,
  );
  res.json({ ok: true });
});

/** Deletes the pairing entirely - only an owner may do this. */
pairingRouter.delete('/:pairingId', requirePairingMembership, (req, res) => {
  const db = getDb();
  const member = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(req.params.pairingId, req.frameId!) as { role: string } | undefined;

  if (member?.role !== 'owner') {
    res.status(403).json({ error: 'only the pairing owner can delete it' });
    return;
  }

  db.prepare('DELETE FROM pairings WHERE id = ?').run(req.params.pairingId);
  res.json({ ok: true });
});
