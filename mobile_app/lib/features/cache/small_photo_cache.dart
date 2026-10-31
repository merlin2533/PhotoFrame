import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../sources/domain/photo_item.dart';
import '../sources/domain/photo_source.dart';

/// Keeps a small, screen-sized JPEG of every photo on the device. The slideshow
/// shows these files, so a photo from a network share is read once and then
/// comes from local storage in full speed.
///
/// Files live in the app support directory and are not cleared on reload.
class SmallPhotoCache {
  SmallPhotoCache({required Future<Directory> Function() directory})
      : _directory = directory;

  final Future<Directory> Function() _directory;

  Future<File> _fileFor(PhotoItem item) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final name = item.stableId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$name.jpg');
  }

  /// The small file if it exists already.
  Future<File?> existing(PhotoItem item) async {
    try {
      final file = await _fileFor(item);
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Makes sure the small file exists: downloads the photo if needed, scales it
  /// down and removes the full-size download. Returns `null` when the photo
  /// cannot be read.
  Future<File?> ensure(PhotoSource source, PhotoItem item) async {
    final have = await existing(item);
    if (have != null) return have;
    try {
      final full = (await source.fetchToCache(item)).valueOrNull;
      if (full == null) return null;
      final target = await _fileFor(item);
      final result = await FlutterImageCompress.compressAndGetFile(
        full.path,
        target.path,
        // Sized for a full-screen tablet (about 2K); larger originals are
        // scaled down, smaller ones stay as they are. Keeps storage small.
        minWidth: 2048,
        minHeight: 2048,
        quality: 90,
      );
      // Downloads of network sources sit in the temp directory; local sources
      // return the original file, which must never be deleted.
      if (full.parent.path == Directory.systemTemp.path &&
          await full.exists()) {
        await full.delete();
      }
      return result == null ? null : File(result.path);
    } catch (_) {
      return null;
    }
  }
}

final Provider<SmallPhotoCache> smallPhotoCacheProvider =
    Provider<SmallPhotoCache>(
  (ref) => SmallPhotoCache(
    directory: () async {
      final base = await getApplicationSupportDirectory();
      return Directory('${base.path}${Platform.pathSeparator}small_photos');
    },
  ),
);

/// Progress of the background job that prepares the small files.
class SmallPhotoStatus {
  const SmallPhotoStatus({this.done = 0, this.total = 0, this.running = false});

  final int done;
  final int total;
  final bool running;
}

/// Prepares the screen-sized copies in batches of [batchSize], one batch after
/// the other. Work can be added at any time with [start]: items that arrive
/// while a run is going are queued and handled by the same run, so the
/// preparation never stops between two refreshes.
class SmallPhotoWorker extends Notifier<SmallPhotoStatus> {
  static const batchSize = 100;

  bool _running = false;
  int _done = 0;
  int _total = 0;
  final Map<String, PhotoItem> _queued = {};
  final Map<String, PhotoSource> _sources = {};

  @override
  SmallPhotoStatus build() => const SmallPhotoStatus();

  /// Queues [items] (in random order) and runs the queue if it is not running.
  /// Returns when the queue is empty.
  Future<void> start(
    List<PhotoItem> items,
    Map<String, PhotoSource> sourcesById,
  ) async {
    _sources.addAll(sourcesById);
    for (final item in List<PhotoItem>.of(items)..shuffle()) {
      if (_queued.putIfAbsent(item.stableId, () => item) == item) {
        _total++;
      }
    }
    if (_running || _queued.isEmpty) return;
    _running = true;
    final cache = ref.read(smallPhotoCacheProvider);
    try {
      while (_queued.isNotEmpty) {
        final batch = _queued.values.take(batchSize).toList();
        for (final item in batch) {
          _queued.remove(item.stableId);
          final source = _sources[item.sourceId];
          // A stalled network read must not stop the whole preparation: after a
          // minute the photo is skipped and the next one starts.
          if (source != null) {
            await cache
                .ensure(source, item)
                .timeout(const Duration(seconds: 60), onTimeout: () => null);
          }
          _done++;
          state = SmallPhotoStatus(
            done: _done,
            total: _total,
            running: true,
          );
        }
        // Give the UI and the slideshow room between batches.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      state = SmallPhotoStatus(done: _done, total: _total);
    } finally {
      _running = false;
    }
  }
}

final NotifierProvider<SmallPhotoWorker, SmallPhotoStatus>
    smallPhotoWorkerProvider =
    NotifierProvider<SmallPhotoWorker, SmallPhotoStatus>(SmallPhotoWorker.new);
