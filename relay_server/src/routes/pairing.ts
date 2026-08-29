import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { getDb, runInTransaction } from '../db';
import { requireDeviceAuth, requirePairingMembership } from '../middleware/authGuard';
import { generatePairingCode, hashPairingCode } from '../auth/pairingCode';
import { deriveKeyFingerprint } from '../auth/keyFingerprint';
import { pairingCreateRateLimiter, pairingRedeemRateLimiter } from '../middleware/rateLimit';
import { releaseImageAccounting } from '../storage/imageCleanup';

export const pairingRouter = Router();

pairingRouter.use(requireDeviceAuth);

// Per docs/PLAN.md ("Ablauf" step 2): 15 minutes, not 10 (Code-Review-Backlog).
const CODE_TTL_MS = 15 * 60 * 1000;
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

  // TOFU fingerprint (PLAN.md "Key-Fingerprint-Verifikation"): derived from
  // the CREATING frame's current public_key and meant to travel out-of-band
  // (e.g. baked into the pairing QR/deep-link as &fp=<fingerprint>), so the
  // joining client can later detect a server-side public_key substitution.
  // A frame that has never completed its keypair setup has no public_key
  // yet - that is a legitimate, expected state (not an error), so we return
  // fp: null plus an explicit fpReason instead of silently omitting the field.
  const creatingFrame = db
    .prepare('SELECT public_key FROM frames WHERE id = ?')
    .get(req.frameId!) as { public_key: string | null } | undefined;
  const fp = deriveKeyFingerprint(creatingFrame?.public_key);

  res.status(201).json({
    pairingId,
    code,
    expiresAt,
    fp,
    ...(fp === null ? { fpReason: 'creating frame has no public_key yet' } : {}),
  });
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

  // Join frames to expose each member's CURRENT public_key fingerprint, so
  // clients can run their own local TOFU comparison against the fingerprint
  // they captured out-of-band at pairing time. The server does not judge
  // whether a fingerprint changed unexpectedly - that decision (and the
  // resulting warning) is entirely client-side, since only the client knows
  // the fingerprint it originally trusted.
  const memberRows = db
    .prepare(
      `SELECT pm.frame_id, pm.role, pm.joined_at, f.public_key
       FROM pairing_members pm
       JOIN frames f ON f.id = pm.frame_id
       WHERE pm.pairing_id = ?`,
    )
    .all(req.params.pairingId) as {
    frame_id: string;
    role: string;
    joined_at: string;
    public_key: string | null;
  }[];

  const members = memberRows.map((m) => ({
    frameId: m.frame_id,
    role: m.role,
    joinedAt: m.joined_at,
    keyFingerprint: deriveKeyFingerprint(m.public_key),
    // Raw public key, needed by a sender to actually encrypt a config-push
    // payload for this member (the fingerprint alone only lets a client
    // verify a key it already has via TOFU, it can't derive the key from
    // it). Public keys are not secret by definition - exposing them to
    // fellow pairing members is safe.
    publicKey: m.public_key,
  }));

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

/**
 * Owner-only removal of another member from the pairing (Code-Review-Backlog
 * Blocker 2, UGC-moderation "block a member" requirement). Deliberately
 * separate from POST /:pairingId/leave: self-removal always goes through
 * /leave so a member never needs owner privileges to remove themselves, and
 * an owner can never accidentally orphan the pairing by "removing" themself
 * through this route instead of an explicit delete/leave/ownership-transfer
 * decision.
 */
pairingRouter.delete('/:pairingId/members/:frameId', requirePairingMembership, (req, res) => {
  const db = getDb();
  const { pairingId, frameId: targetFrameId } = req.params;

  const caller = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(pairingId, req.frameId!) as { role: string } | undefined;

  if (caller?.role !== 'owner') {
    res.status(403).json({ error: 'only the pairing owner can remove members' });
    return;
  }

  if (targetFrameId === req.frameId) {
    res.status(400).json({ error: 'use POST /:pairingId/leave to remove yourself' });
    return;
  }

  const target = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(pairingId, targetFrameId);

  if (!target) {
    res.status(404).json({ error: 'that frame is not a member of this pairing' });
    return;
  }

  db.prepare('DELETE FROM pairing_members WHERE pairing_id = ? AND frame_id = ?').run(
    pairingId,
    targetFrameId,
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

  // Release blob refcounts + storage_used_bytes for every image in this
  // pairing BEFORE the cascade delete below removes the `images` rows -
  // `ON DELETE CASCADE` alone deletes the rows but knows nothing about
  // blobs.refcount/users.storage_used_bytes, which used to leak here
  // (Code-Review-Backlog). Both run in one transaction so a crash between
  // the two never leaves the counters out of sync with what was deleted.
  const images = db
    .prepare('SELECT content_hash, uploaded_by_frame_id FROM images WHERE pairing_id = ?')
    .all(req.params.pairingId) as { content_hash: string; uploaded_by_frame_id: string }[];

  runInTransaction(db, () => {
    releaseImageAccounting(images);
    db.prepare('DELETE FROM pairings WHERE id = ?').run(req.params.pairingId);
  });
  res.json({ ok: true });
});
