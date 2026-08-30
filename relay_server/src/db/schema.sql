-- PhotoFrame relay server schema.
-- Applied idempotently by the migration runner (src/db/migrations).
-- NOTE: journal_mode/synchronous/foreign_keys/busy_timeout pragmas are set
-- once by src/db/index.ts before migrations run (SQLite disallows changing
-- journal_mode/synchronous from inside a transaction, which migrations run in).

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  storage_used_bytes INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS frames (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  public_key TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  last_seen_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_frames_user_id ON frames(user_id);

CREATE TABLE IF NOT EXISTS device_tokens (
  id TEXT PRIMARY KEY,
  frame_id TEXT NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  last_seen_at TEXT,
  revoked_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_frame_id ON device_tokens(frame_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_token_hash ON device_tokens(token_hash);

CREATE TABLE IF NOT EXISTS pairings (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS pairing_members (
  pairing_id TEXT NOT NULL REFERENCES pairings(id) ON DELETE CASCADE,
  frame_id TEXT NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('owner', 'member')),
  joined_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (pairing_id, frame_id)
);

CREATE INDEX IF NOT EXISTS idx_pairing_members_frame_id ON pairing_members(frame_id);

-- pairing_codes: code_hash is HMAC-SHA256(pepper, code) so it stays indexable
-- for a direct lookup on redemption (bcrypt would preclude that).
CREATE TABLE IF NOT EXISTS pairing_codes (
  code_hash TEXT PRIMARY KEY,
  pairing_id TEXT NOT NULL REFERENCES pairings(id) ON DELETE CASCADE,
  created_by_frame_id TEXT REFERENCES frames(id) ON DELETE SET NULL,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS config_pushes (
  id TEXT PRIMARY KEY,
  target_frame_id TEXT NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  sender_frame_id TEXT NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  ciphertext TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  applied_at TEXT,
  rejected_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_config_pushes_target ON config_pushes(target_frame_id, applied_at, rejected_at);

-- blobs: explicit refcount table backing the content-addressed store,
-- instead of COUNT(*) over images (cheap reads, no race on delete).
CREATE TABLE IF NOT EXISTS blobs (
  hash TEXT PRIMARY KEY,
  bytes INTEGER NOT NULL,
  refcount INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS images (
  id TEXT PRIMARY KEY,
  pairing_id TEXT NOT NULL REFERENCES pairings(id) ON DELETE CASCADE,
  uploaded_by_frame_id TEXT NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  content_hash TEXT NOT NULL REFERENCES blobs(hash),
  uploaded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  width INTEGER,
  height INTEGER,
  -- client_upload_id idempotency is scoped per-frame, not global - see
  -- migrations/002_scope_client_upload_id.sql. This file mirrors the schema
  -- after all migrations, so no column-level UNIQUE here; the constraint is
  -- the composite index below.
  client_upload_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_images_pairing_id ON images(pairing_id, uploaded_at);
CREATE INDEX IF NOT EXISTS idx_images_content_hash ON images(content_hash);
CREATE UNIQUE INDEX IF NOT EXISTS idx_images_upload_scope ON images(uploaded_by_frame_id, client_upload_id);

CREATE TABLE IF NOT EXISTS image_hidden (
  image_id TEXT NOT NULL REFERENCES images(id) ON DELETE CASCADE,
  frame_id TEXT NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  hidden_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (image_id, frame_id)
);

CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY,
  image_id TEXT NOT NULL REFERENCES images(id) ON DELETE CASCADE,
  reporter_frame_id TEXT NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_reports_image_id ON reports(image_id);

CREATE TABLE IF NOT EXISTS admin_audit (
  id TEXT PRIMARY KEY,
  actor TEXT NOT NULL,
  action TEXT NOT NULL,
  target_type TEXT,
  target_id TEXT,
  at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
