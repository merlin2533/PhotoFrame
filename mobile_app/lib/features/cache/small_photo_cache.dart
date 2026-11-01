import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/app_log.dart';
import '../settings/state/settings_providers.dart';
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

  /// The one shared FIFO queue for ALL heavy image work of this cache: decoding
  /// for checks ([verify], [colorGrid]), scaling (native and Flutter) and the
  /// colour comparison after scaling. At most one such job runs at a time, and
  /// jobs run in the order they were queued. Entry points that take the queue:
  /// [verifiedExisting] (the verify step) and [ensure] (the scaling step, which
  /// includes its colour checks).
  ///
  /// Jobs run inside the queue must NOT call [_serial] again: the inner call
  /// would wait for the job that is waiting for it. [colorGrid], [verify] and
  /// [looksLikeOriginal] are plain functions for that reason.
  ///
  /// The lock is taken before the job starts, and the timeout ([scaleTimeout])
  /// applies to the job only, not to the wait for the previous job, so a queued
  /// job never times out while it is still waiting. A stuck native call that
  /// exceeds the timeout still runs in the background and may overlap with the
  /// next job, which is accepted.
  Future<void> _queueTail = Future<void>.value();

  /// After this duration a queued job counts as failed and the lock is
  /// released.
  static const scaleTimeout = Duration(seconds: 45);

  Future<T> _serial<T>(Future<T> Function() job) {
    final done = Completer<void>();
    final previous = _queueTail;
    _queueTail = done.future;
    return previous
        .then((_) => job().timeout(scaleTimeout))
        .whenComplete(() => done.complete());
  }

  /// Runs [job] through the shared queue, exactly like the internal jobs do.
  /// Only for tests, to occupy the queue with a controllable job.
  @visibleForTesting
  Future<T> runInQueueForTest<T>(Future<T> Function() job) => _serial(job);

  /// Keeps the temporary file names of concurrent calls apart.
  int _tempCounter = 0;

  bool _purgedOldVersion = false;

  /// Earlier versions stored copies with an unchecked, sometimes purple
  /// colour cast and kept no original to compare with, so the old folder is
  /// dropped once and everything is prepared again.
  Future<void> _purgeOldVersion(Directory dir) async {
    if (_purgedOldVersion) return;
    _purgedOldVersion = true;
    for (final name in legacyDirectoryNames) {
      final old = Directory('${dir.parent.path}${Platform.pathSeparator}$name');
      try {
        if (await old.exists()) await old.delete(recursive: true);
      } catch (e, st) {
        logRecoverableError(
          'Old small photo folder could not be removed',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  /// Name of the folder used before colours were checked (see above).
  // The live folder is 'small_photos_v3'. Older folders are removed; listing
  // the live folder here would delete the whole cache on every start.
  static const legacyDirectoryNames = ['small_photos', 'small_photos_v2'];
  static const liveDirectoryName = 'small_photos_v3';

  /// Removes every prepared copy so they are created again.
  Future<void> clear() async {
    final dir = await _directory();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<File> _fileFor(PhotoItem item) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    await _purgeOldVersion(dir);
    final name = baseNameFor(item.stableId);
    return File('${dir.path}${Platform.pathSeparator}$name.jpg');
  }

  /// File name (without `.jpg`) used for a stableId: every character outside
  /// `[A-Za-z0-9_-]` becomes `_`. A stableId is `<sourceId>:<hash>`, so the
  /// name starts with `<sourceId>_` (see [belongsToSource]).
  static String baseNameFor(String stableId) =>
      stableId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// The stableId hash is 16 lowercase hex characters (see `MediaStableId`).
  static final RegExp _fileSuffix = RegExp(r'^[0-9a-f]{16}\.jpg$');

  /// `true` when the cache file [fileName] was written for a photo of
  /// [sourceId]. Source ids may contain `_`, so the prefix alone is not
  /// enough: the rest of the name must be exactly one 16-character hash.
  static bool belongsToSource(String fileName, String sourceId) {
    final prefix = baseNameFor('$sourceId:');
    if (!fileName.startsWith(prefix)) return false;
    return _fileSuffix.hasMatch(fileName.substring(prefix.length));
  }

  /// The first of [knownSourceIds] that [fileName] belongs to, or `null` when
  /// it belongs to none (for example a source that was removed).
  static String? sourceIdForFile(
    String fileName,
    Iterable<String> knownSourceIds,
  ) {
    for (final id in knownSourceIds) {
      if (belongsToSource(fileName, id)) return id;
    }
    return null;
  }

  /// Every regular file in the cache folder. Empty while the folder does not
  /// exist yet.
  Future<List<File>> _cachedFiles() async {
    final dir = await _directory();
    if (!await dir.exists()) return [];
    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    return files;
  }

  static String _nameOf(File file) => file.path.split(RegExp(r'[/\\]')).last;

  /// Counts and sizes of the whole folder, grouped by [knownSourceIds]. Every
  /// known source gets an entry (even with 0 files); files that match none of
  /// them are summed up separately as "unassigned" instead of being dropped.
  Future<SmallPhotoCacheUsage> usage(Iterable<String> knownSourceIds) async {
    final ids = knownSourceIds.toSet().toList();
    final counts = {for (final id in ids) id: 0};
    final bytes = {for (final id in ids) id: 0};
    var unassignedCount = 0;
    var unassignedBytes = 0;
    for (final file in await _cachedFiles()) {
      final size = await _sizeOf(file);
      if (size == null) continue;
      final id = sourceIdForFile(_nameOf(file), ids);
      if (id == null) {
        unassignedCount++;
        unassignedBytes += size;
      } else {
        counts[id] = counts[id]! + 1;
        bytes[id] = bytes[id]! + size;
      }
    }
    return SmallPhotoCacheUsage(
      bySource: [
        for (final id in ids)
          SmallPhotoSourceUsage(
            sourceId: id,
            count: counts[id]!,
            bytes: bytes[id]!,
          ),
      ],
      unassignedCount: unassignedCount,
      unassignedBytes: unassignedBytes,
    );
  }

  /// Size in bytes, or `null` when the file vanished meanwhile (for example
  /// removed by a concurrent clear).
  static Future<int?> _sizeOf(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return null;
    }
  }

  /// Deletes the cache files of [sourceId] only. Returns how many were removed.
  Future<int> deleteForSource(String sourceId) =>
      _deleteWhere((name) => belongsToSource(name, sourceId));

  /// Deletes the files that belong to none of [knownSourceIds] (left behind by
  /// removed sources). Returns how many were removed.
  Future<int> deleteUnassigned(Iterable<String> knownSourceIds) {
    final ids = knownSourceIds.toList();
    return _deleteWhere((name) => sourceIdForFile(name, ids) == null);
  }

  Future<int> _deleteWhere(bool Function(String fileName) matches) async {
    var deleted = 0;
    for (final file in await _cachedFiles()) {
      if (!matches(_nameOf(file))) continue;
      try {
        await file.delete();
        deleted++;
      } on FileSystemException catch (e, st) {
        logRecoverableError(
          'Small photo could not be deleted',
          error: e,
          stackTrace: st,
        );
      }
    }
    return deleted;
  }

  /// Path of the small file of [item] (it may not exist).
  Future<File> fileFor(PhotoItem item) => _fileFor(item);

  /// Files that passed [verify], keyed by path and remembered with their size
  /// and modification time so a good file is not decoded again on every show.
  final Map<String, String> _verified = {};

  /// The small file of [item], but only if it exists AND is intact (complete
  /// JPEG/PNG that decodes fully). A damaged file is deleted so it is
  /// prepared again, and `null` is returned.
  ///
  /// The stamp is checked before the queue, so a repeat check of a verified
  /// file returns at once even while a scaling runs. The decoding check itself
  /// waits in the shared queue (see [_serial]).
  Future<File?> verifiedExisting(PhotoItem item) async {
    final file = await existing(item);
    if (file == null) return null;
    try {
      final stat = await file.stat();
      final stamp = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
      if (_verified[file.path] == stamp) return file;
      // The stamp is checked again inside the queue: another call may have
      // verified the same file while this one was waiting.
      final ok = await _serial(() async {
        if (_verified[file.path] == stamp) return true;
        return verify(file);
      });
      if (ok) {
        _verified[file.path] = stamp;
        return file;
      }
    } catch (_) {}
    _verified.remove(file.path);
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    return null;
  }

  /// `true` when [file] is a complete image that decodes without error.
  /// A plain function: [verifiedExisting] runs it inside the shared queue, so
  /// it must not take the queue itself.
  static Future<bool> verify(File file) async {
    if (!await looksComplete(file, 0)) return false;
    return await colorGrid(file) != null;
  }

  /// The small file if it exists already.
  Future<File?> existing(PhotoItem item) async {
    try {
      final file = await _fileFor(item);
      return await file.exists() ? file : null;
    } catch (e, st) {
      logRecoverableError(
        'Small photo lookup failed',
        error: e,
        stackTrace: st,
      );
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
      var full = (await source.fetchToCache(item)).valueOrNull;
      // A download that is cut off (network share hiccup) must never become a
      // small copy: check it is complete, and try once more if not.
      if (full != null && !await looksComplete(full, 0)) {
        await _deleteIfTemp(full);
        full = (await source.fetchToCache(item)).valueOrNull;
        if (full != null && !await looksComplete(full, 0)) {
          await _deleteIfTemp(full);
          return null;
        }
      }
      if (full == null) return null;
      // A local variable so the promotion survives the closure below.
      final download = full;
      final target = await _fileFor(item);
      // Written to a temporary name first: a half-written or broken file must
      // never be picked up by [existing] and shown in the slideshow.
      // Unique per call, so two concurrent calls for the same item never share
      // (and delete) each other's temp file. The .jpg suffix stays: decoders
      // and the compressor pick the format from it.
      final temp = File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}'
        '_${_tempCounter++}.tmp.jpg',
      );
      File? small;
      try {
        // Scaling and its colour checks run as one job of the shared queue.
        small = await _serial(() => _scale(download, temp));
        if (small == null) return null;
        if (await target.exists()) await target.delete();
        await small.rename(target.path);
      } finally {
        if (await temp.exists()) await temp.delete();
        // Downloads of network sources sit in the temp directory; local
        // sources return the original file, which must never be deleted.
        if (full.parent.path == Directory.systemTemp.path &&
            await full.exists()) {
          await full.delete();
        }
      }
      return target;
    } catch (e, st) {
      logRecoverableError(
        'Small photo could not be prepared',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<void> _deleteIfTemp(File file) async {
    if (file.parent.path == Directory.systemTemp.path && await file.exists()) {
      await file.delete();
    }
  }

  /// `false` when [file] is empty, is a JPEG without an end marker (FF D9
  /// anywhere in the file, so data appended after it, such as the video of a
  /// motion photo, is fine), or is a PNG whose last chunk is not IEND.
  ///
  /// [expectedSize] is only compared when [downloadIsOriginal] is set: a
  /// source may deliver a smaller preview than the size it reports for the
  /// original, so the size is ignored for every other download.
  static Future<bool> looksComplete(
    File file,
    int expectedSize, {
    bool downloadIsOriginal = false,
  }) async {
    try {
      final length = await file.length();
      if (length == 0) return false;
      if (downloadIsOriginal && expectedSize > 0 && length < expectedSize) {
        return false;
      }
      final raf = await file.open();
      try {
        final head = await raf.read(8);
        if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8) {
          return await _hasJpegEndMarker(raf, length);
        }
        if (head.length >= 4 && head[0] == 0x89 && head[1] == 0x50) {
          // PNG: last chunk is IEND.
          final tailLen = length < 64 ? length : 64;
          await raf.setPosition(length - tailLen);
          final tail = await raf.read(tailLen);
          return String.fromCharCodes(tail).contains('IEND');
        }
        return true; // other formats: only the size check applies
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// `true` when the file contains a JPEG end marker (FF D9). The file is
  /// searched backwards in 64 KiB chunks, so the last marker is found first
  /// and the whole file is read only when there is none.
  static Future<bool> _hasJpegEndMarker(
    RandomAccessFile raf,
    int length,
  ) async {
    const chunk = 64 * 1024;
    var end = length;
    while (end > 0) {
      final start = end > chunk ? end - chunk : 0;
      // One byte past [end] is read as well, so a marker split at the chunk
      // border is found.
      final stop = end < length ? end + 1 : end;
      await raf.setPosition(start);
      final bytes = await raf.read(stop - start);
      for (var i = bytes.length - 2; i >= 0; i--) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) return true;
      }
      end = start;
    }
    return false;
  }

  /// Runs only as a job of the shared queue (see [ensure]). Native scaling,
  /// the colour checks and the Flutter fallback all happen in this one job.
  Future<File?> _scale(File full, File temp) async {
    File? small;
    final result = await FlutterImageCompress.compressAndGetFile(
      full.path,
      temp.path,
      // Sized for a full-screen tablet (about 2K); larger originals are
      // scaled down, smaller ones stay as they are. Keeps storage small.
      minWidth: 2048,
      minHeight: 2048,
      quality: 90,
    );
    if (result != null) {
      final out = File(result.path);
      // The native scaler mishandles some files (CMYK, odd colour profiles)
      // and produces a purple/colour-cast picture. Compare the average colour
      // with the original and reject such results.
      if (await looksLikeOriginal(full, out)) small = out;
    }
    return small ?? await _scaleWithFlutter(full, temp);
  }

  /// Grid size of the colour comparison: the picture is split into
  /// [gridSize] x [gridSize] cells so damage in one part of the picture (for
  /// example a garbled left third) is noticed, not averaged away.
  static const gridSize = 6;

  /// Average colour (r, g, b) of every cell of a [gridSize] x [gridSize] grid
  /// of [file], decoded small by Flutter's own codec (a full decode of the
  /// data, so truncated or broken files fail here). `null` when the file
  /// cannot be decoded.
  ///
  /// A plain function that does not take the queue lock: it is only called
  /// from jobs that already run inside the shared queue ([verify] via
  /// [verifiedExisting], and [_scale] via [ensure]).
  static Future<List<List<double>>?> colorGrid(File file) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: gridSize * 8,
      );
      final image = (await codec.getNextFrame()).image;
      final w = image.width, h = image.height;
      final data = await image.toByteData();
      image.dispose();
      if (data == null || w < gridSize || h < gridSize) return null;
      final sums = List.generate(gridSize * gridSize, (_) => [0.0, 0.0, 0.0]);
      final counts = List.filled(gridSize * gridSize, 0);
      for (var y = 0; y < h; y++) {
        final row = (y * gridSize ~/ h) * gridSize;
        for (var x = 0; x < w; x++) {
          final cell = row + (x * gridSize ~/ w);
          final o = (y * w + x) * 4;
          for (var c = 0; c < 3; c++) {
            sums[cell][c] += data.getUint8(o + c);
          }
          counts[cell]++;
        }
      }
      return [
        for (var k = 0; k < sums.length; k++)
          [for (final v in sums[k]) v / (counts[k] == 0 ? 1 : counts[k])],
      ];
    } catch (_) {
      // Undecodable file: expected for some formats, so this is not logged
      // as an error. The caller falls back to the placeholder.
      return null;
    } finally {
      codec?.dispose();
    }
  }

  /// `true` when [scaled] decodes and matches [original]: the overall average
  /// colour is close and no single cell of the grid differs strongly. If the
  /// original itself cannot be decoded by Flutter there is nothing to compare
  /// against, so the scaled file is accepted when it decodes.
  /// Plain function: only called from [_scale], which runs inside the shared
  /// queue, so it must not take the queue itself.
  static Future<bool> looksLikeOriginal(File original, File scaled) async {
    final b = await colorGrid(scaled);
    if (b == null) return false;
    final a = await colorGrid(original);
    if (a == null) return true;
    final mean = [0.0, 0.0, 0.0];
    for (var k = 0; k < a.length; k++) {
      for (var c = 0; c < 3; c++) {
        final d = (a[k][c] - b[k][c]).abs();
        if (d > 60) return false; // one cell clearly wrong
        mean[c] += (a[k][c] - b[k][c]) / a.length;
      }
    }
    return mean.every((m) => m.abs() <= 30);
  }

  /// Fallback scaler using Flutter's own decoder (correct colours for every
  /// format it can read), re-encoded as JPEG to keep storage small.
  Future<File?> _scaleWithFlutter(File source, File temp) async {
    ui.Codec? codec;
    try {
      final bytes = await source.readAsBytes();
      // The size is read from the header only (no full decode), and the
      // image is then decoded once, already scaled.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final w = descriptor.width, h = descriptor.height;
        final longest = w > h ? w : h;
        codec = longest > 2048
            ? await descriptor.instantiateCodec(
                targetWidth: w >= h ? 2048 : null,
                targetHeight: h > w ? 2048 : null,
              )
            : await descriptor.instantiateCodec();
      } finally {
        descriptor.dispose();
        buffer.dispose();
      }
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      // Flutter decoded the colours correctly; the PNG is only handed to the
      // native encoder, which turns it into a small JPEG (no colour
      // conversion on this path, so the cast cannot come back).
      final jpeg = await FlutterImageCompress.compressWithList(
        Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
        minWidth: 2048,
        minHeight: 2048,
        quality: 90,
        format: CompressFormat.jpeg,
      );
      return await temp.writeAsBytes(jpeg, flush: true);
    } catch (e, st) {
      logRecoverableError(
        'Fallback photo scaling failed',
        error: e,
        stackTrace: st,
      );
      return null;
    } finally {
      codec?.dispose();
    }
  }
}

final Provider<SmallPhotoCache> smallPhotoCacheProvider =
    Provider<SmallPhotoCache>(
  (ref) => SmallPhotoCache(
    directory: () async {
      final base = await getApplicationSupportDirectory();
      return Directory(
        '${base.path}${Platform.pathSeparator}${SmallPhotoCache.liveDirectoryName}',
      );
    },
  ),
);

/// Number and total size of the cached files of one source.
class SmallPhotoSourceUsage {
  const SmallPhotoSourceUsage({
    required this.sourceId,
    required this.count,
    required this.bytes,
  });

  final String sourceId;
  final int count;
  final int bytes;
}

/// What the small-photo cache holds right now, see [SmallPhotoCache.usage].
class SmallPhotoCacheUsage {
  const SmallPhotoCacheUsage({
    required this.bySource,
    required this.unassignedCount,
    required this.unassignedBytes,
  });

  /// One entry per known source, in the order the source ids were given.
  final List<SmallPhotoSourceUsage> bySource;

  /// Files that belong to none of the known sources.
  final int unassignedCount;
  final int unassignedBytes;

  int get count => bySource.fold(unassignedCount, (sum, s) => sum + s.count);

  int get totalBytes =>
      bySource.fold(unassignedBytes, (sum, s) => sum + s.bytes);
}

/// Progress of the background job that prepares the small files.
class SmallPhotoStatus {
  const SmallPhotoStatus({
    this.done = 0,
    this.total = 0,
    this.running = false,
    this.waiting = 0,
  });

  final int done;
  final int total;
  final bool running;

  /// Photos still waiting in the queue behind the one being prepared.
  final int waiting;
}

/// Prepares the screen-sized copies in batches (size from the settings), one batch after
/// the other. Work can be added at any time with [start]: items that arrive
/// while a run is going are queued and handled by the same run, so the
/// preparation never stops between two refreshes.
class SmallPhotoWorker extends Notifier<SmallPhotoStatus> {
  /// Default batch size; the real value comes from the settings.
  static const defaultBatchSize = 5;

  /// A photo that could not be prepared is left alone for this long before it
  /// is tried again.
  static const retryAfter = Duration(hours: 1);

  bool _running = false;
  int _done = 0;
  int _total = 0;
  final Map<String, PhotoItem> _queued = {};
  final Map<String, PhotoSource> _sources = {};

  /// stableIds of photos whose small copy exists (prepared in this session).
  final Set<String> _doneKeys = {};

  /// When each photo last failed to prepare.
  final Map<String, DateTime> _failedAt = {};

  @override
  SmallPhotoStatus build() => const SmallPhotoStatus();

  /// Forgets what was prepared or failed (used after the copies were deleted,
  /// so nothing is skipped as "already done").
  void reset() {
    _doneKeys.clear();
    _failedAt.clear();
  }

  /// Forgets that [item] was prepared (its small file turned out damaged), so
  /// it is prepared again at the front of the queue.
  Future<void> reprepare(PhotoItem item, PhotoSource source) {
    _doneKeys.remove(item.stableId);
    _failedAt.remove(item.stableId);
    return prioritize(item, source);
  }

  bool _failedRecently(PhotoItem item) {
    final failed = _failedAt[item.stableId];
    return failed != null && DateTime.now().difference(failed) < retryAfter;
  }

  /// Queues [items] (in random order) and runs the queue if it is not running.
  /// Returns when the queue is empty.
  Future<void> start(
    List<PhotoItem> items,
    Map<String, PhotoSource> sourcesById,
  ) async {
    _sources.addAll(sourcesById);
    for (final item in List<PhotoItem>.of(items)..shuffle()) {
      if (_queued.containsKey(item.stableId)) continue;
      if (_doneKeys.contains(item.stableId) || _failedRecently(item)) continue;
      _queued[item.stableId] = item;
      _total++;
    }
    await _run();
  }

  /// Puts [item] at the front of the queue and runs the queue if it is not
  /// running, so a photo about to be shown is prepared before the others.
  /// Photos that are already prepared or failed recently are left alone.
  Future<void> prioritize(PhotoItem item, PhotoSource source) async {
    _sources[source.id] = source;
    if (_doneKeys.contains(item.stableId) || _failedRecently(item)) return;
    final wasQueued = _queued.containsKey(item.stableId);
    final rest = Map<String, PhotoItem>.of(_queued)..remove(item.stableId);
    _queued
      ..clear()
      ..[item.stableId] = item
      ..addAll(rest);
    if (!wasQueued) _total++;
    await _run();
  }

  /// Works through the queue batch by batch until it is empty. Does nothing
  /// when a run is already going: that run picks up what was queued meanwhile.
  Future<void> _run() async {
    if (_running || _queued.isEmpty) return;
    _running = true;
    final cache = ref.read(smallPhotoCacheProvider);
    try {
      while (_queued.isNotEmpty) {
        final batchSize =
            (ref.read(settingsProvider).value?.smallPhotoBatchSize ??
                    defaultBatchSize)
                .clamp(1, 50);
        final batch = _queued.values.take(batchSize).toList();
        for (final item in batch) {
          _queued.remove(item.stableId);
          final source = _sources[item.sourceId];
          // A stalled network read must not stop the whole preparation: after a
          // minute the photo is skipped and the next one starts.
          if (source != null) {
            final file = await cache
                .ensure(source, item)
                .timeout(const Duration(seconds: 60), onTimeout: () => null);
            if (file != null) {
              _doneKeys.add(item.stableId);
              _failedAt.remove(item.stableId);
            } else {
              _failedAt[item.stableId] = DateTime.now();
            }
          }
          _done++;
          state = SmallPhotoStatus(
            done: _done,
            total: _total,
            running: true,
            waiting: _queued.length,
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
    NotifierProvider<SmallPhotoWorker, SmallPhotoStatus>(
  SmallPhotoWorker.new,
);
