-- Adds the refresh_tokens table (previously created ad hoc by
-- auth/userAuth.ts on every call), the missing foreign-key lookup indexes,
-- and makes device_tokens.token_hash unique.
--
-- Everything here is additive or an index swap, so no table rebuild and no
-- FK toggling is needed (contrast with 002, which had to rebuild `images`).
-- All statements are idempotent (IF NOT EXISTS / IF EXISTS) so a database
-- where the ad hoc refresh_tokens table already exists is handled cleanly.

CREATE TABLE IF NOT EXISTS refresh_tokens (
  jti TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  revoked_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);

-- Foreign-key columns used in WHERE and cascade paths without an index.
CREATE INDEX IF NOT EXISTS idx_images_uploaded_by_frame_id ON images(uploaded_by_frame_id);
CREATE INDEX IF NOT EXISTS idx_image_hidden_frame_id ON image_hidden(frame_id);
CREATE INDEX IF NOT EXISTS idx_config_pushes_sender_frame_id ON config_pushes(sender_frame_id);
CREATE INDEX IF NOT EXISTS idx_reports_reporter_frame_id ON reports(reporter_frame_id);
CREATE INDEX IF NOT EXISTS idx_pairing_codes_pairing_id ON pairing_codes(pairing_id);

-- Used by the maintenance job to delete expired pairing codes.
CREATE INDEX IF NOT EXISTS idx_pairing_codes_expires_at ON pairing_codes(expires_at);

-- Used by the admin audit log ordering and any future time-range pruning.
CREATE INDEX IF NOT EXISTS idx_admin_audit_at ON admin_audit(at);

-- token_hash is looked up on every device-authenticated request. The previous
-- index was non-unique; replacing it with a UNIQUE one keeps the lookup fast
-- and enforces that a token hash maps to exactly one device token.
DROP INDEX IF EXISTS idx_device_tokens_token_hash;
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_tokens_token_hash ON device_tokens(token_hash);
