-- Scopes client_upload_id idempotency to the uploading frame instead of
-- enforcing it globally unique across every frame in the system.
--
-- Rationale: a global UNIQUE on client_upload_id means any two frames in the
-- entire deployment (unrelated pairings, unrelated users) share one
-- namespace of upload ids. A frame that submits (or guesses) a
-- client_upload_id already used by another frame either gets rejected on
-- insert (denial of service against a legitimate upload) or, worse, the
-- dedup lookup in routes/images.ts (`SELECT id FROM images WHERE
-- client_upload_id = ?`, unscoped) hands back someone else's imageId as if
-- it were "their" freshly-deduped upload - a cross-tenant id disclosure.
-- Scoping the uniqueness (and the dedup lookup) to
-- (uploaded_by_frame_id, client_upload_id) keeps idempotent retries working
-- per-frame while removing the cross-frame coupling entirely.
--
-- SQLite has no ALTER TABLE ... DROP CONSTRAINT / ALTER COLUMN, and the
-- column-level UNIQUE on client_upload_id was declared in the CREATE TABLE
-- itself, so the standard SQLite migration pattern is used: rebuild the
-- table without that constraint, copy the data across unchanged, drop the
-- old table, rename the new one into place, and recreate every index that
-- previously existed on images (idx_images_pairing_id,
-- idx_images_content_hash), plus the new composite unique index.
--
-- CORRECTION (found by review, verified by actually running this migration
-- against seeded image_hidden/reports rows): an earlier version of this
-- comment claimed FK enforcement is deferred until COMMIT and the
-- CASCADE-referencing tables (image_hidden, reports) are therefore
-- untouched. That is WRONG, and so is `PRAGMA defer_foreign_keys = ON` as a
-- fix within this transaction: `DROP TABLE images` performs an implicit
-- `DELETE FROM images` for every row, and `ON DELETE CASCADE` triggers fire
-- immediately for that delete regardless of `defer_foreign_keys` (which
-- only postpones dangling-reference *validation* to COMMIT, not cascade
-- *actions*). The only way to prevent that is to disable FK enforcement
-- entirely for the duration of the rebuild - which SQLite only allows
-- outside an active transaction - so this is now handled by the migration
-- runner itself (`db/migrations/index.ts` toggles
-- `PRAGMA foreign_keys = OFF` before BEGIN and back to `ON` after COMMIT
-- for every migration), not by anything in this file.

CREATE TABLE images_new (
  id TEXT PRIMARY KEY,
  pairing_id TEXT NOT NULL REFERENCES pairings(id) ON DELETE CASCADE,
  uploaded_by_frame_id TEXT NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  content_hash TEXT NOT NULL REFERENCES blobs(hash),
  uploaded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  width INTEGER,
  height INTEGER,
  client_upload_id TEXT
);

INSERT INTO images_new (id, pairing_id, uploaded_by_frame_id, content_hash, uploaded_at, width, height, client_upload_id)
  SELECT id, pairing_id, uploaded_by_frame_id, content_hash, uploaded_at, width, height, client_upload_id
  FROM images;

DROP TABLE images;

ALTER TABLE images_new RENAME TO images;

CREATE INDEX IF NOT EXISTS idx_images_pairing_id ON images(pairing_id, uploaded_at);
CREATE INDEX IF NOT EXISTS idx_images_content_hash ON images(content_hash);

-- Replaces the old global UNIQUE(client_upload_id): idempotency is now
-- per-frame. NULLs (rows uploaded before client_upload_id existed, or any
-- future upload path that omits it) are not compared against each other by
-- SQLite's UNIQUE index semantics, so multiple NULL client_upload_id rows
-- for the same frame remain allowed, matching the old column-level UNIQUE's
-- behavior.
CREATE UNIQUE INDEX IF NOT EXISTS idx_images_upload_scope ON images(uploaded_by_frame_id, client_upload_id);
