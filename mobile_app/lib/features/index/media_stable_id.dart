import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Computes a stable identifier for a media item in the form
/// `sourceId:pathHash`, as anticipated in `docs/PLAN.md` under "P2 –
/// Spätere Härtung": *"Favoriten / 'nie wieder zeigen' – stabile Item-IDs
/// (sourceId + pathHash) jetzt festlegen, Feature später"*.
///
/// The id is derived only from [sourceId] and the source-relative path, so
/// it stays stable across app restarts and re-crawls as long as the file's
/// path relative to its source doesn't change - independent of other
/// metadata (size, mtime, cache state) that may legitimately change between
/// crawls. It is used to key favorites, "on this day" bookkeeping, and the
/// playlist `excludeIds` filter (see `features/playlists/playlist.dart`).
///
/// The hash is truncated to 16 hex characters (64 bits) purely to keep the
/// id short for use as a `SharedPreferences`/JSON key; this is not a
/// security-sensitive hash, only a stable-identity one.
class MediaStableId {
  const MediaStableId._();

  static String compute({required String sourceId, required String path}) {
    final digest = sha256.convert(utf8.encode(path));
    final shortHash = digest.toString().substring(0, 16);
    return '$sourceId:$shortHash';
  }
}
