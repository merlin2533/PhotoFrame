import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
    } catch (_) {
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

  /// Average colour (r, g, b) of [file] decoded at a tiny size by Flutter's own
  /// codec, or `null` when it cannot be decoded.
  static Future<List<double>?> averageColor(File file) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: 16,
      );
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData();
      image.dispose();
      if (data == null) return null;
      final sum = [0.0, 0.0, 0.0];
      final pixels = data.lengthInBytes ~/ 4;
      if (pixels == 0) return null;
      for (var i = 0; i < pixels; i++) {
        for (var c = 0; c < 3; c++) {
          sum[c] += data.getUint8(i * 4 + c);
        }
      }
      return [for (final v in sum) v / pixels];
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
    }
  }

  /// `true` when [scaled] decodes and its average colour is close to that of
  /// [original]. If the original itself cannot be decoded by Flutter there is
  /// nothing to compare against, so the scaled file is accepted when it
  /// decodes.
  static Future<bool> looksLikeOriginal(File original, File scaled) async {
    final b = await averageColor(scaled);
    if (b == null) return false;
    final a = await averageColor(original);
    if (a == null) return true;
    for (var c = 0; c < 3; c++) {
      if ((a[c] - b[c]).abs() > 30) return false;
    }
    return true;
  }

  /// Fallback scaler using Flutter's own decoder (correct colours for every
  /// format it can read). Stored as PNG data: larger, but always right.
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
      final out = await temp.writeAsBytes(
          Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
          flush: true);
      return out;
    } catch (_) {
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

/// Prepares the screen-sized copies in batches of [batchSize], one batch after
/// the other. Work can be added at any time with [start]: items that arrive
/// while a run is going are queued and handled by the same run, so the
/// preparation never stops between two refreshes.
class SmallPhotoWorker extends Notifier<SmallPhotoStatus> {
  static const batchSize = 20;

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
