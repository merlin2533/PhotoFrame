import 'dart:io';

import '../../../core/errors/failure.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/result.dart';
import '../domain/media_type.dart';
import '../domain/photo_folder.dart';
import '../domain/photo_item.dart';
import '../domain/photo_source.dart';

/// Fully in-memory [PhotoSource] used for development and tests.
///
/// Generates a deterministic set of folders/items on construction and
/// simulates realistic async behaviour (small artificial delays) without
/// touching the network or filesystem beyond writing a placeholder file for
/// [fetchToCache].
class MockPhotoSource implements PhotoSource {
  MockPhotoSource({
    String? id,
    String? displayName,
    int folderCount = 2,
    int itemsPerFolder = 10,
    Directory? cacheDirectory,
    this.simulatedDelay = const Duration(milliseconds: 20),
  })  : id = id ?? 'mock-source',
        displayName = displayName ?? 'Mock Source',
        _cacheDirectory = cacheDirectory {
    _generateContent(folderCount, itemsPerFolder);
  }

  @override
  final String id;

  @override
  final String displayName;

  @override
  SourceType get type => SourceType.mock;

  /// Artificial latency applied to every simulated async operation, so UI
  /// code exercising loading states behaves realistically in dev/tests.
  final Duration simulatedDelay;

  final Directory? _cacheDirectory;

  final List<PhotoFolder> _folders = [];
  final Map<String, List<PhotoItem>> _itemsByFolderId = {};

  bool _disposed = false;

  void _generateContent(int folderCount, int itemsPerFolder) {
    for (var f = 0; f < folderCount; f++) {
      final folder = PhotoFolder(
        id: 'folder-$f',
        name: 'Mock Folder $f',
        path: '/mock/folder-$f',
      );
      _folders.add(folder);

      final items = <PhotoItem>[];
      for (var i = 0; i < itemsPerFolder; i++) {
        items.add(
          PhotoItem(
            id: 'folder-$f-item-$i',
            sourceId: id,
            folderId: folder.id,
            name: 'mock_${f}_$i.jpg',
            mediaType: MediaType.image,
            width: 1920,
            height: 1080,
            takenAt: DateTime(2024, 1, 1).add(Duration(days: f * itemsPerFolder + i)),
            orientation: 1,
            size: 1024 * 1024,
            mtime: DateTime(2024, 1, 1).add(Duration(days: f * itemsPerFolder + i)),
          ),
        );
      }
      _itemsByFolderId[folder.id] = items;
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('MockPhotoSource "$id" has already been disposed');
    }
  }

  @override
  Future<Result<ConnectionStatus>> testConnection({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _checkNotDisposed();
    await Future<void>.delayed(simulatedDelay);
    return Result.ok(
      const ConnectionStatus(
        reachable: true,
        latency: Duration(milliseconds: 5),
        detail: 'mock source always reachable',
      ),
    );
  }

  @override
  Stream<Result<PhotoFolder>> listFolders({
    PhotoFolder? parent,
    CancellationToken? token,
  }) async* {
    _checkNotDisposed();
    // The mock source only ever has a flat list of root folders.
    if (parent != null) {
      return;
    }
    for (final folder in _folders) {
      token?.throwIfCancelled();
      await Future<void>.delayed(simulatedDelay);
      yield Result.ok(folder);
    }
  }

  @override
  Stream<Result<PhotoItem>> listImages(
    PhotoFolder folder, {
    bool recursive = true,
    CancellationToken? token,
  }) async* {
    _checkNotDisposed();
    final items = _itemsByFolderId[folder.id];
    if (items == null) {
      yield Result.err(NotFound('Unknown mock folder: ${folder.id}'));
      return;
    }
    for (final item in items) {
      token?.throwIfCancelled();
      await Future<void>.delayed(simulatedDelay);
      yield Result.ok(item);
    }
  }

  @override
  Future<Result<File>> fetchToCache(
    PhotoItem item, {
    CancellationToken? token,
  }) async {
    _checkNotDisposed();
    await Future<void>.delayed(simulatedDelay);
    token?.throwIfCancelled();

    final allItems = _itemsByFolderId[item.folderId];
    if (allItems == null || !allItems.any((i) => i.id == item.id)) {
      return Result.err(NotFound('Unknown mock item: ${item.id}'));
    }

    try {
      final dir = _cacheDirectory ?? Directory.systemTemp;
      final file = File('${dir.path}${Platform.pathSeparator}${item.id}.jpg');
      if (!await file.exists()) {
        // Write a tiny, deterministic placeholder payload rather than a
        // real image - good enough for exercising cache/IO plumbing.
        await file.writeAsBytes(
          List<int>.generate(64, (i) => (item.id.hashCode + i) & 0xff),
          flush: true,
        );
      }
      return Result.ok(file);
    } on FileSystemException catch (e) {
      return Result.err(NetworkError('Failed to write mock cache file', cause: e));
    }
  }

  /// The mock source never pushes changes. See the doc comment on
  /// [PhotoSource.changes] for why most sources behave this way; here it is
  /// simply hard-coded to a stream that never emits, closed only on
  /// [dispose].
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _folders.clear();
    _itemsByFolderId.clear();
  }
}
