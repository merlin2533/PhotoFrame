import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

  /// Scaling runs strictly one photo at a time: a photo whose wait timed out
  /// still holds this lock until its native scaling has really finished, so
  /// two scalings never overlap.
  Future<void> _scalingTail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() job) {
    final done = Completer<void>();
    final previous = _scalingTail;
    _scalingTail = done.future;
    return previous.then((_) => job()).whenComplete(done.complete);
  }

  bool _purgedOldVersion = false;

  /// Earlier versions stored copies with an unchecked, sometimes purple
  /// colour cast and kept no original to compare with, so the old folder is
  /// dropped once and everything is prepared again.
  Future<void> _purgeOldVersion(Directory dir) async {
    if (_purgedOldVersion) return;
    _purgedOldVersion = true;
    final old = Directory(
        '${dir.parent.path}${Platform.pathSeparator}$legacyDirectoryName');
    try {
      if (await old.exists()) await old.delete(recursive: true);
    } catch (e, st) {
      logRecoverableError('Old small photo folder could not be removed',
          error: e, stackTrace: st);
    }
  }

  /// Name of the folder used before colours were checked (see above).
  static const legacyDirectoryName = 'small_photos';

  /// Removes every prepared copy so they are created again.
  Future<void> clear() async {
    final dir = await _directory();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<File> _fileFor(PhotoItem item) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    await _purgeOldVersion(dir);
    final name = item.stableId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$name.jpg');
  }

  /// The small file if it exists already.
  Future<File?> existing(PhotoItem item) async {
    try {
      final file = await _fileFor(item);
      return await file.exists() ? file : null;
    } catch (e, st) {
      logRecoverableError('Small photo lookup failed', error: e, stackTrace: st);
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
      // Written to a temporary name first: a half-written or broken file must
      // never be picked up by [existing] and shown in the slideshow.
      final temp = File('${target.path}.tmp.jpg');
      if (await temp.exists()) await temp.delete();
      File? small;
      try {
        small = await _serial(() => _scale(full, temp));
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
      logRecoverableError('Small photo could not be prepared',
          error: e, stackTrace: st);
      return null;
    }
  }

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
      final probe = await ui.instantiateImageCodec(bytes);
      final frame = (await probe.getNextFrame()).image;
      final w = frame.width, h = frame.height;
      frame.dispose();
      probe.dispose();
      final longest = w > h ? w : h;
      codec = longest > 2048
          ? await ui.instantiateImageCodec(bytes,
              targetWidth: w >= h ? 2048 : null,
              targetHeight: h > w ? 2048 : null)
          : await ui.instantiateImageCodec(bytes);
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
      logRecoverableError('Fallback photo scaling failed',
          error: e, stackTrace: st);
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
      return Directory('${base.path}${Platform.pathSeparator}small_photos');
    },
  ),
);

/// Progress of the background job that prepares the small files.
class SmallPhotoStatus {
  const SmallPhotoStatus(
      {this.done = 0, this.total = 0, this.running = false, this.waiting = 0});

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
        final batchSize = (ref
                    .read(settingsProvider)
                    .value
                    ?.smallPhotoBatchSize ??
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
    NotifierProvider<SmallPhotoWorker, SmallPhotoStatus>(SmallPhotoWorker.new);
