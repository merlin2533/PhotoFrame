import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/app_log.dart';
import '../../core/utils/debug_trace.dart';
import '../settings/state/settings_providers.dart';
import '../sources/domain/media_type.dart';
import '../sources/domain/photo_item.dart';
import '../sources/domain/photo_source.dart';
import '../sources/local/local_folder_source.dart';
import 'download_rate_meter.dart';
import 'not_convertible_store.dart';
import 'slideshow_busy.dart';

/// Thrown by [SmallPhotoCache.ensure] when a photo can never become a
/// screen-sized copy. The worker marks such a photo as not convertible and
/// never tries it again.
///
/// [cause] is set when the scaling step threw. It is `null` for the expected
/// refusals (video, format other than JPEG/PNG, no file from scaling), which
/// are not logged as errors.
class PhotoNotConvertibleException implements Exception {
  const PhotoNotConvertibleException(this.reason,
      {this.cause, this.stackTrace});

  final String reason;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'PhotoNotConvertibleException: $reason';
}

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

  /// Jobs of the shared queue that are running or waiting for their turn.
  int _openConversions = 0;

  /// Scaling and verification jobs that are running or waiting in the shared
  /// queue right now.
  int get openConversions => _openConversions;

  /// Bytes downloaded by [ensure] since this cache was created. A cache hit
  /// and a local source (which returns the original file) add nothing.
  int _downloadedBytes = 0;

  int get downloadedBytes => _downloadedBytes;

  /// After this duration a queued job counts as failed and the lock is
  /// released.
  static const scaleTimeout = Duration(seconds: 45);

  Future<T> _serial<T>(Future<T> Function() job) {
    final done = Completer<void>();
    final previous = _queueTail;
    _queueTail = done.future;
    _openConversions++;
    return previous.then((_) => job().timeout(scaleTimeout)).whenComplete(() {
      _openConversions--;
      done.complete();
    });
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
  /// down and removes the full-size download.
  ///
  /// [beforeScale] is awaited after the download and before the scaling job
  /// is queued. The worker uses it to hold back scaling while the slideshow is
  /// busy; downloads are never held.
  ///
  /// Returns `null` when the download failed (a retry later may succeed).
  /// Throws [PhotoNotConvertibleException] when the photo can never be scaled:
  /// it is a video, it is not a JPEG or PNG, or the scaling step returned no
  /// file or threw. The caller must not retry such a photo.
  Future<File?> ensure(
    PhotoSource source,
    PhotoItem item, {
    Future<void> Function()? beforeScale,
  }) async {
    final name = DebugTrace.baseName(item.id);
    DebugTrace.event('cache', 'ensure start $name');
    try {
      final result = await _ensure(source, item, beforeScale: beforeScale);
      DebugTrace.event(
          'cache', 'ensure end $name ${result == null ? 'no file' : 'ok'}');
      return result;
    } on PhotoNotConvertibleException {
      DebugTrace.event('cache', 'ensure end $name not convertible');
      rethrow;
    } catch (e) {
      DebugTrace.event('cache', 'ensure end $name threw ${e.runtimeType}');
      rethrow;
    }
  }

  /// The body of [ensure]; see there.
  Future<File?> _ensure(
    PhotoSource source,
    PhotoItem item, {
    Future<void> Function()? beforeScale,
  }) async {
    final have = await existing(item);
    if (have != null) return have;
    // Videos have no still image to scale: refused without a download.
    if (item.mediaType == MediaType.video) {
      throw const PhotoNotConvertibleException('Video, no still image');
    }
    try {
      var full = (await source.fetchToCache(item)).valueOrNull;
      await _countDownload(source, full);
      // A download that is cut off (network share hiccup) must never become a
      // small copy: check it is complete, and try once more if not.
      if (full != null && !await looksComplete(full, 0)) {
        await deleteIfTemp(full);
        full = (await source.fetchToCache(item)).valueOrNull;
        await _countDownload(source, full);
        if (full != null && !await looksComplete(full, 0)) {
          await deleteIfTemp(full);
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
        // Safety rule: only JPEG and PNG files reach the scaler. Checked
        // before the busy wait, so a refused photo never waits.
        if (!await isScalableFormat(download)) {
          throw const PhotoNotConvertibleException(
              'Format is neither JPEG nor PNG');
        }
        // Panoramas are not scaled: the native scaler damages parts of very
        // wide or very tall images, and the colour check cannot see that.
        // They are shown as the original instead.
        final w = item.width, h = item.height;
        if (w != null && h != null && h > 0 && w > 0) {
          final ratio = w / h;
          if (ratio > 2.5 || ratio < 0.4) {
            throw const PhotoNotConvertibleException(
                'Extreme aspect ratio (panorama), not scaled');
          }
        }
        // Held back while the slideshow is busy. Waiting happens before the
        // job takes its place in the shared queue, so a slideshow decode is
        // never stuck behind a waiting scale.
        await beforeScale?.call();
        small = await _scaleInQueue(download, temp);
        if (small == null) {
          throw const PhotoNotConvertibleException('Scaling returned no file');
        }
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
    } on PhotoNotConvertibleException {
      rethrow;
    } catch (e, st) {
      logRecoverableError(
        'Small photo could not be prepared',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Runs [_scale] as one job of the shared queue. Any failure of the job
  /// (including the timeout of [scaleTimeout]) becomes a
  /// [PhotoNotConvertibleException] with the original error as [cause].
  Future<File?> _scaleInQueue(File download, File temp) async {
    try {
      // Scaling and its colour checks run as one job of the shared queue.
      return await _serial(() => scaleCopy(download, temp));
    } catch (e, st) {
      throw PhotoNotConvertibleException(
        'Scaling threw an exception',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// `true` when the first bytes of [file] are a JPEG (FF D8 FF) or a PNG
  /// (89 50 4E 47). Other formats are never decoded. A file that cannot be
  /// read counts as not scalable.
  static Future<bool> isScalableFormat(File file) async {
    try {
      final raf = await file.open();
      try {
        return isScalableHeader(await raf.read(4));
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// The pure check behind [isScalableFormat], on the first bytes of a file.
  static bool isScalableHeader(List<int> head) {
    final jpeg = head.length >= 3 &&
        head[0] == 0xFF &&
        head[1] == 0xD8 &&
        head[2] == 0xFF;
    final png = head.length >= 4 &&
        head[0] == 0x89 &&
        head[1] == 0x50 &&
        head[2] == 0x4E &&
        head[3] == 0x47;
    return jpeg || png;
  }

  /// Adds the size of [file], as returned by [PhotoSource.fetchToCache], to
  /// [downloadedBytes]. Local folder sources return the original file, which
  /// was not downloaded, so they add nothing. A file whose length cannot be
  /// read counts as 0.
  Future<void> _countDownload(PhotoSource source, File? file) async {
    if (file == null || source is LocalFolderSource) return;
    try {
      _downloadedBytes += await file.length();
    } catch (_) {}
  }

  /// Deletes [file] only when it sits in the temp directory, where downloads
  /// of network sources go. Local originals are never deleted.
  Future<void> deleteIfTemp(File file) async {
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

  /// Scales [full] into [temp]: the scaling step of [ensure]. Only called as a
  /// job of the shared queue. Overridable so tests can observe when scaling
  /// starts.
  @visibleForTesting
  Future<File?> scaleCopy(File full, File temp) => _scale(full, temp);

  /// Runs only as a job of the shared queue (see [ensure]). Native scaling,
  /// the colour checks and the Flutter fallback all happen in this one job.
  Future<File?> _scale(File full, File temp) async {
    final name = DebugTrace.baseName(full.path);
    File? small;
    var colourRejected = false;
    try {
      DebugTrace.event('cache', 'native scale start $name');
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
        if (await looksLikeOriginal(full, out)) {
          small = out;
          DebugTrace.event('cache', 'native scale end $name ok');
        } else {
          colourRejected = true;
          DebugTrace.event('cache', 'native scale end $name colour rejected');
        }
      } else {
        DebugTrace.event('cache', 'native scale end $name no file');
      }
    } catch (e, st) {
      DebugTrace.event(
          'cache', 'native scale end $name threw ${e.runtimeType}');
      // The native plugin throws on some files (a null reference inside the
      // plugin). That must not fail the photo: the Flutter path below can
      // still scale it.
      logRecoverableError('Native photo scaling failed, using the fallback',
          error: e, stackTrace: st);
    }
    // A colour-rejected photo is not decoded by the Flutter engine: on large
    // camera files that decode crashed the app. It counts as not convertible,
    // and the original is shown instead.
    // The Flutter fallback is disabled: its decode of the engine crashed the app
    // on photos where the native scaler threw (also small ones). Such a photo
    // counts as not convertible and the original is shown instead.
    if (colourRejected || small == null) return null;
    return small;
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
  // ignore: unused_element
  Future<File?> _scaleWithFlutter(File source, File temp) async {
    final name = DebugTrace.baseName(source.path);
    DebugTrace.event('cache', 'flutter scale start $name');
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
      if (data == null) {
        DebugTrace.event('cache', 'flutter scale end $name no data');
        return null;
      }
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
      final written = await temp.writeAsBytes(jpeg, flush: true);
      DebugTrace.event('cache', 'flutter scale end $name ok');
      return written;
    } catch (e, st) {
      DebugTrace.event(
          'cache', 'flutter scale exception $name ${e.runtimeType}');
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
    this.downloadedBytes = 0,
    this.downloadRate = 0,
    this.openConversions = 0,
  });

  final int done;
  final int total;
  final bool running;

  /// Photos still waiting in the queue behind the one being prepared.
  final int waiting;

  /// Bytes downloaded by the current run so far.
  final int downloadedBytes;

  /// Download speed in bytes per second, averaged over the last ~10 seconds.
  /// `0` when nothing is downloaded.
  final double downloadRate;

  /// Scaling and verification jobs open right now (running or waiting for the
  /// shared queue).
  final int openConversions;
}

/// Prepares the screen-sized copies in batches (size from the settings), one batch after
/// the other. Work can be added at any time with [start]: items that arrive
/// while a run is going are queued and handled by the same run, so the
/// preparation never stops between two refreshes.
///
/// Failures are handled in two ways:
/// - A failed download is retried after [retryAfter] (hourly).
/// - A photo that cannot be scaled (see [PhotoNotConvertibleException]) is
///   written to the persistent [NotConvertibleStore] and never scaled again.
class SmallPhotoWorker extends Notifier<SmallPhotoStatus> {
  /// Default batch size; the real value comes from the settings.
  static const defaultBatchSize = 5;

  /// A photo whose download failed is left alone for this long before it is
  /// tried again. Scaling failures are not retried at all.
  static const retryAfter = Duration(hours: 1);

  /// Pause between two items of the queue. Downloads and scaling never run
  /// back-to-back, and the slideshow gets idle time in between.
  static const itemPause = Duration(milliseconds: 1500);

  /// How often the worker checks [slideshowBusyProvider] while it waits to
  /// scale a photo.
  static const busyPollInterval = Duration(milliseconds: 300);

  /// Longest wait for the slideshow to become idle before a scaling starts
  /// anyway (per item).
  static const maxBusyWait = Duration(seconds: 30);

  bool _running = false;
  int _done = 0;
  int _total = 0;
  final Map<String, PhotoItem> _queued = {};
  final Map<String, PhotoSource> _sources = {};

  /// Set by [stop] while a run is going; the run ends after the current photo.
  bool _stopRequested = false;

  /// stableIds of photos whose small copy exists (prepared in this session).
  final Set<String> _doneKeys = {};

  /// When each photo last failed to download.
  final Map<String, DateTime> _failedAt = {};

  /// Download speed of the current run, sampled by [_run]'s publish step.
  final DownloadRateMeter _rateMeter = DownloadRateMeter();

  NotConvertibleStore get _notConvertible =>
      ref.read(notConvertibleStoreProvider);

  @override
  SmallPhotoStatus build() => const SmallPhotoStatus();

  /// Forgets what was prepared or failed (used after the copies were deleted,
  /// so nothing is skipped as "already done"). Photos marked as not
  /// convertible stay marked.
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
    final notConvertible = await _notConvertible.load();
    for (final item in List<PhotoItem>.of(items)..shuffle()) {
      if (_queued.containsKey(item.stableId)) continue;
      if (_doneKeys.contains(item.stableId) ||
          _failedRecently(item) ||
          notConvertible.contains(item.stableId)) {
        continue;
      }
      _queued[item.stableId] = item;
      _total++;
    }
    await _run();
  }

  /// Puts [item] at the front of the queue and runs the queue if it is not
  /// running, so a photo about to be shown is prepared before the others.
  /// Photos that are already prepared, not convertible or failed recently are
  /// left alone.
  Future<void> prioritize(PhotoItem item, PhotoSource source) async {
    _sources[source.id] = source;
    if (_doneKeys.contains(item.stableId) || _failedRecently(item)) return;
    if (await _notConvertible.contains(item.stableId)) return;
    final wasQueued = _queued.containsKey(item.stableId);
    final rest = Map<String, PhotoItem>.of(_queued)..remove(item.stableId);
    _queued
      ..clear()
      ..[item.stableId] = item
      ..addAll(rest);
    if (!wasQueued) _total++;
    await _run();
  }

  /// Ends the current run after the photo that is being prepared, and drops
  /// the photos still waiting in the queue. Does nothing when no run is going.
  void stop() {
    if (!_running) return;
    _stopRequested = true;
    _queued.clear();
  }

  /// Marks [item] as not convertible, in memory and persistently.
  Future<void> _markNotConvertible(PhotoItem item) async {
    await _notConvertible.add(item.stableId);
  }

  /// Waits while the slideshow is busy (see [slideshowBusyProvider]), polling
  /// every [busyPollInterval]. Gives up after [maxBusyWait] and returns, so the
  /// preparation cannot stall for good. Uses only timers (no clock), so it
  /// works under fake async in tests.
  Future<void> _waitForSlideshow() async {
    var waited = Duration.zero;
    final busy = ref.read(slideshowBusyProvider);
    while (busy.busy && waited < maxBusyWait) {
      await Future<void>.delayed(busyPollInterval);
      waited += busyPollInterval;
    }
  }

  /// Runs [_waitForSlideshow] for tests.
  @visibleForTesting
  Future<void> waitForSlideshowForTest() => _waitForSlideshow();

  /// Works through the queue batch by batch until it is empty. Does nothing
  /// when a run is already going: that run picks up what was queued meanwhile.
  Future<void> _run() async {
    if (_running || _queued.isEmpty) return;
    _running = true;
    final cache = ref.read(smallPhotoCacheProvider);
    _rateMeter.reset();
    final bytesAtStart = cache.downloadedBytes;

    // Publishes the live counters. Called after every photo and by the timer
    // below, so the download rate moves while a large photo is downloading.
    void publish() {
      _rateMeter.add(DateTime.now(), cache.downloadedBytes);
      state = SmallPhotoStatus(
        done: _done,
        total: _total,
        running: true,
        waiting: _queued.length,
        downloadedBytes: cache.downloadedBytes - bytesAtStart,
        downloadRate: _rateMeter.bytesPerSecond,
        openConversions: cache.openConversions,
      );
    }

    final ticker = Timer.periodic(const Duration(seconds: 1), (_) => publish());
    // False until the first item of this run has started, so the pause below
    // sits between two items only (also across batches).
    var anyItemStarted = false;
    try {
      while (_queued.isNotEmpty && !_stopRequested) {
        final batchSize =
            (ref.read(settingsProvider).value?.smallPhotoBatchSize ??
                    defaultBatchSize)
                .clamp(1, 50);
        final batch = _queued.values.take(batchSize).toList();
        for (final item in batch) {
          if (_stopRequested) break;
          if (anyItemStarted) {
            // Give the UI and the slideshow room between two items.
            await Future<void>.delayed(itemPause);
            if (_stopRequested) break;
          }
          anyItemStarted = true;
          _queued.remove(item.stableId);
          final traceName = DebugTrace.baseName(item.id);
          DebugTrace.event('worker', 'item start $traceName');
          var outcome = 'skipped';
          final source = _sources[item.sourceId];
          // A stalled network read must not stop the whole preparation: after a
          // minute the photo is skipped and the next one starts. The wait for an
          // idle slideshow ([maxBusyWait]) is added to that minute, so a photo
          // that waited for the slideshow is not counted as stalled.
          if (source != null &&
              !await _notConvertible.contains(item.stableId)) {
            try {
              final file = await cache
                  .ensure(source, item, beforeScale: _waitForSlideshow)
                  .timeout(
                    const Duration(seconds: 60) + maxBusyWait,
                    onTimeout: () => null,
                  );
              outcome = file == null ? 'no file' : 'ok';
              if (file != null) {
                _doneKeys.add(item.stableId);
                _failedAt.remove(item.stableId);
              } else {
                // Download failed: retried after [retryAfter].
                _failedAt[item.stableId] = DateTime.now();
              }
            } on PhotoNotConvertibleException catch (e) {
              outcome = 'not convertible';
              // Never scaled again. Only real scaling errors are logged; the
              // expected refusals (video, other formats) are not errors.
              if (e.cause != null) {
                logRecoverableError(
                  'Photo could not be scaled, marked as not convertible',
                  error: e.cause,
                  stackTrace: e.stackTrace,
                );
              }
              await _markNotConvertible(item);
            } catch (e, st) {
              outcome = 'error ${e.runtimeType}';
              // Anything else must not stop the worker: log it, mark the
              // photo, and go on with the next one.
              logRecoverableError(
                'Photo preparation failed, marked as not convertible',
                error: e,
                stackTrace: st,
              );
              await _markNotConvertible(item);
            }
          }
          DebugTrace.event('worker', 'item end $traceName $outcome');
          _done++;
          publish();
        }
      }
      _total = _done + _queued.length;
      state = SmallPhotoStatus(done: _done, total: _total);
    } finally {
      ticker.cancel();
      _running = false;
      _stopRequested = false;
    }
  }
}

final NotifierProvider<SmallPhotoWorker, SmallPhotoStatus>
    smallPhotoWorkerProvider =
    NotifierProvider<SmallPhotoWorker, SmallPhotoStatus>(
  SmallPhotoWorker.new,
);
