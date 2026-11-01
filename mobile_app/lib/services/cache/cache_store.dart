import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The areas of the central cache. Each area is a folder below the cache
/// root, so the same source can have files in several areas.
enum CacheArea {
  /// Original files downloaded from a source.
  downloads('downloads'),

  /// Derived copies (e.g. screen-sized JPEGs) prepared from the downloads.
  prepared('prepared');

  const CacheArea(this.folderName);

  /// Name of the folder below the cache root.
  final String folderName;
}

/// Per-source number of files and bytes in the cache.
///
/// [sourceId] is null for the unassigned entry, which collects folders whose
/// source id is not among the known ids.
class CacheSourceUsage {
  const CacheSourceUsage({
    required this.sourceId,
    this.fileCounts = const <CacheArea, int>{},
    this.byteCounts = const <CacheArea, int>{},
  });

  /// The raw source id, or null for the unassigned entry.
  final String? sourceId;

  /// Number of regular files per area. Areas without files are absent.
  final Map<CacheArea, int> fileCounts;

  /// Total size in bytes per area. Areas without files are absent.
  final Map<CacheArea, int> byteCounts;

  /// Number of files over all areas.
  int get count => fileCounts.values.fold(0, (a, b) => a + b);

  /// Size in bytes over all areas.
  int get bytes => byteCounts.values.fold(0, (a, b) => a + b);

  /// Number of files in [area], 0 if there are none.
  int countIn(CacheArea area) => fileCounts[area] ?? 0;

  /// Size in bytes in [area], 0 if there are none.
  int bytesIn(CacheArea area) => byteCounts[area] ?? 0;
}

/// Snapshot of the central cache, as returned by [CacheStore.usage].
class CacheUsage {
  const CacheUsage({required this.sources, required this.unassigned});

  /// One entry per known source id, including sources without any files.
  final List<CacheSourceUsage> sources;

  /// Folders whose source id is not among the known ids.
  final CacheSourceUsage unassigned;

  /// Size in bytes of all files in the cache, assigned or not.
  int get totalBytes =>
      sources.fold(0, (sum, s) => sum + s.bytes) + unassigned.bytes;

  /// Number of files in the cache, assigned or not.
  int get totalCount =>
      sources.fold(0, (sum, s) => sum + s.count) + unassigned.count;
}

/// Central store for cached files, shared by all sources.
///
/// Layout: `<root>/<area>/<safeSourceId>/<safeKey>.<ext>`, where `<area>` is
/// the [CacheArea.folderName]. Only the file name for a key is derived from
/// the key, so the same key always maps to the same file.
///
/// Writers that must not leave a half-written file behind should write to a
/// unique temp file in the same folder as the target and then call
/// [commit]. A suggested pattern is
/// `'${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp'`. The temp
/// file must be in the same folder so that the rename is atomic.
class CacheStore {
  CacheStore({
    required Future<Directory> Function() root,
    int? Function()? limitBytes,
  })  : _root = root,
        _limitBytes = limitBytes;

  final Future<Directory> Function() _root;
  final int? Function()? _limitBytes;

  /// Configured size limit in bytes, or null if there is none. No eviction
  /// is done by this class yet.
  int? get limitBytes => _limitBytes?.call();

  /// Turns [raw] into a name that is safe as a single path segment.
  ///
  /// Every character outside `[A-Za-z0-9_-]` becomes `_`. If anything changed
  /// (or [raw] is empty), `_` and the first 8 hex characters of the sha256 of
  /// [raw] are appended, so different raw ids such as `a:b` and `a_b` do not
  /// collide after sanitizing.
  static String safeName(String raw) {
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (raw.isNotEmpty && safe == raw) return raw;
    final hash = sha256.convert(utf8.encode(raw)).toString().substring(0, 8);
    return '${safe}_$hash';
  }

  /// Returns the deterministic file for [key] of [sourceId] in [area]. The
  /// parent folder is created if it does not exist. The file itself is not
  /// created.
  ///
  /// [ext] is a plain extension without the dot and may only contain ASCII
  /// letters and digits.
  Future<File> fileFor(
    CacheArea area,
    String sourceId,
    String key, {
    String ext = 'jpg',
  }) async {
    final file = await _pathFor(area, sourceId, key, ext);
    await file.parent.create(recursive: true);
    return file;
  }

  /// Returns the file for [key] if it exists, otherwise null. On a hit the
  /// mtime is set to now, so that it counts as recently used. Errors while
  /// touching the file are ignored.
  Future<File?> existing(
    CacheArea area,
    String sourceId,
    String key, {
    String ext = 'jpg',
  }) async {
    final file = await _pathFor(area, sourceId, key, ext);
    if (!await file.exists()) return null;
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // Best effort only: the file is still a valid hit.
    }
    return file;
  }

  /// Moves [tmp] to [target] and returns the file at [target].
  ///
  /// An existing [target] is replaced. On POSIX systems the rename replaces
  /// it atomically. Where rename does not replace existing files, the old
  /// target is deleted and the rename is tried again. [tmp] and [target]
  /// should be in the same folder (see the class documentation).
  Future<File> commit(File tmp, File target) async {
    try {
      return await tmp.rename(target.path);
    } on FileSystemException {
      if (!await target.exists()) rethrow;
      await target.delete();
      return tmp.rename(target.path);
    }
  }

  /// Counts files and bytes per area and per known source id.
  ///
  /// Only regular files are counted. Folders of unknown source ids are
  /// collected in [CacheUsage.unassigned]. Loose files directly in an area
  /// folder are ignored. A folder or file that disappears during the scan is
  /// skipped.
  Future<CacheUsage> usage(Iterable<String> knownSourceIds) async {
    final root = await _root();
    final knownBySafe = <String, String>{
      for (final id in knownSourceIds) safeName(id): id,
    };
    final counts = <String?, Map<CacheArea, int>>{};
    final bytes = <String?, Map<CacheArea, int>>{};
    for (final id in knownBySafe.values) {
      counts[id] = <CacheArea, int>{};
      bytes[id] = <CacheArea, int>{};
    }
    counts[null] = <CacheArea, int>{};
    bytes[null] = <CacheArea, int>{};

    for (final area in CacheArea.values) {
      final areaDir = Directory(_join([root.path, area.folderName]));
      if (!await areaDir.exists()) continue;
      await for (final sourceDir in _listDirectories(areaDir)) {
        final name = _baseName(sourceDir.path);
        final owner = knownBySafe[name];
        await for (final entity in _listFiles(sourceDir, recursive: true)) {
          final size = await _sizeOf(entity);
          if (size == null) continue;
          counts[owner]![area] = (counts[owner]![area] ?? 0) + 1;
          bytes[owner]![area] = (bytes[owner]![area] ?? 0) + size;
        }
      }
    }

    CacheSourceUsage entry(String? id) => CacheSourceUsage(
          sourceId: id,
          fileCounts: Map.unmodifiable(counts[id]!),
          byteCounts: Map.unmodifiable(bytes[id]!),
        );

    return CacheUsage(
      sources: [for (final id in knownBySafe.values) entry(id)],
      unassigned: entry(null),
    );
  }

  /// Recursively deletes the folder of [sourceId], in [area] or in all areas.
  /// Other sources are not touched. Returns the number of files removed.
  Future<int> deleteForSource(String sourceId, {CacheArea? area}) async {
    final root = await _root();
    var removed = 0;
    for (final a in _areas(area)) {
      final dir =
          Directory(_join([root.path, a.folderName, safeName(sourceId)]));
      if (!await dir.exists()) continue;
      await for (final entity in _listFiles(dir, recursive: true)) {
        if (await _sizeOf(entity) != null) removed++;
      }
      await dir.delete(recursive: true);
    }
    return removed;
  }

  /// Deletes everything in [area], or in all areas if [area] is null.
  Future<void> clear({CacheArea? area}) async {
    final root = await _root();
    for (final a in _areas(area)) {
      final dir = Directory(_join([root.path, a.folderName]));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  Iterable<CacheArea> _areas(CacheArea? area) =>
      area == null ? CacheArea.values : [area];

  Future<File> _pathFor(
      CacheArea area, String sourceId, String key, String ext) async {
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(ext)) {
      throw ArgumentError.value(ext, 'ext', 'must be letters and digits only');
    }
    final root = await _root();
    return File(_join([
      root.path,
      area.folderName,
      safeName(sourceId),
      '${safeName(key)}.$ext',
    ]));
  }

  static String _join(List<String> parts) => parts.join(Platform.pathSeparator);

  static String _baseName(String path) =>
      path.split(Platform.pathSeparator).last;

  /// Subfolders of [dir]. A listing that fails (e.g. the folder vanished) is
  /// treated as empty.
  static Stream<Directory> _listDirectories(Directory dir) async* {
    final entities = await _tryList(dir, recursive: false);
    for (final e in entities) {
      if (e is Directory) yield e;
    }
  }

  /// Regular files below [dir]. Symbolic links are not followed and not
  /// returned.
  static Stream<File> _listFiles(Directory dir,
      {required bool recursive}) async* {
    final entities = await _tryList(dir, recursive: recursive);
    for (final e in entities) {
      if (e is File) yield e;
    }
  }

  static Future<List<FileSystemEntity>> _tryList(Directory dir,
      {required bool recursive}) async {
    try {
      return await dir.list(recursive: recursive, followLinks: false).toList();
    } on FileSystemException {
      return const [];
    }
  }

  /// Size of [file] in bytes, or null if it is not a regular file or has
  /// vanished.
  static Future<int?> _sizeOf(FileSystemEntity file) async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return stat.size;
    } on FileSystemException {
      return null;
    }
  }
}

/// The central cache store. The root is `<ApplicationSupport>/photo_cache`.
///
/// Provider is lazy: nothing is created or read until it is first used.
final Provider<CacheStore> cacheStoreProvider = Provider<CacheStore>(
  (ref) => CacheStore(
    root: () async {
      final base = await getApplicationSupportDirectory();
      return Directory('${base.path}${Platform.pathSeparator}photo_cache');
    },
  ),
);
