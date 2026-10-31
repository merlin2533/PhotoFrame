import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../sources/domain/media_type.dart';
import '../sources/domain/photo_item.dart';

/// Persists the list of photos found by the last crawl, so the next start can
/// show the slideshow from the saved index immediately and only refresh it in
/// the background (see `SlideshowScreen`).
///
/// Stored as one JSON document. Reading or writing never throws to the
/// caller: a missing or corrupt index simply means "no index yet".
/// The saved photo list and when it was built.
class IndexSnapshot {
  const IndexSnapshot({required this.items, required this.savedAt});

  static final empty = IndexSnapshot(
    items: const [],
    savedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final List<PhotoItem> items;
  final DateTime savedAt;

  Duration age(DateTime now) => now.difference(savedAt);
}

class PhotoIndexStore {
  PhotoIndexStore({
    required Future<String?> Function() read,
    required Future<void> Function(String json) write,
  })  : _read = read,
        _write = write;

  final Future<String?> Function() _read;
  final Future<void> Function(String json) _write;

  /// Loads the saved index. An empty snapshot (no items, epoch time) means
  /// "no index yet".
  Future<IndexSnapshot> load() async {
    try {
      final raw = await _read();
      if (raw == null) return IndexSnapshot.empty;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final items = [
        for (final e in map['items'] as List)
          _itemFromJson(e as Map<String, dynamic>),
      ];
      return IndexSnapshot(
        items: items,
        savedAt: DateTime.fromMillisecondsSinceEpoch(map['savedAt'] as int),
      );
    } catch (_) {
      return IndexSnapshot.empty;
    }
  }

  Future<void> save(List<PhotoItem> items, {DateTime? savedAt}) async {
    try {
      await _write(jsonEncode({
        'savedAt': (savedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'items': [for (final i in items) _itemToJson(i)],
      }));
    } catch (_) {
      // Best effort: the index is rebuilt by the next crawl anyway.
    }
  }

  /// Forgets the saved index, so the next load triggers a full crawl.
  Future<void> clear() =>
      save(const [], savedAt: DateTime.fromMillisecondsSinceEpoch(0));

  static Map<String, dynamic> _itemToJson(PhotoItem i) => {
        'id': i.id,
        'sourceId': i.sourceId,
        'folderId': i.folderId,
        'name': i.name,
        'mediaType': i.mediaType.name,
        'size': i.size,
        'mtime': i.mtime.millisecondsSinceEpoch,
        'width': i.width,
        'height': i.height,
        'takenAt': i.takenAt?.millisecondsSinceEpoch,
        'orientation': i.orientation,
      };

  static PhotoItem _itemFromJson(Map<String, dynamic> j) => PhotoItem(
        id: j['id'] as String,
        sourceId: j['sourceId'] as String,
        folderId: j['folderId'] as String,
        name: j['name'] as String,
        mediaType: MediaType.values.byName(j['mediaType'] as String),
        size: j['size'] as int,
        mtime: DateTime.fromMillisecondsSinceEpoch(j['mtime'] as int),
        width: j['width'] as int?,
        height: j['height'] as int?,
        takenAt: j['takenAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['takenAt'] as int),
        orientation: j['orientation'] as int? ?? 0,
      );

  /// File-backed store in the app support directory.
  static PhotoIndexStore file() => PhotoIndexStore(
        read: () async {
          final f = await _indexFile();
          return await f.exists() ? f.readAsString() : null;
        },
        write: (json) async => (await _indexFile()).writeAsString(json),
      );

  static Future<File> _indexFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}photo_index_v1.json');
  }
}

/// Overridden in widget tests with an in-memory store.
final Provider<PhotoIndexStore> photoIndexStoreProvider =
    Provider<PhotoIndexStore>((ref) => PhotoIndexStore.file());
