import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/utils/result.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../cache/not_convertible_store.dart';
import '../../../cache/small_photo_cache.dart';
import '../../../settings/domain/app_settings.dart';
import '../../../settings/state/settings_providers.dart';
import '../../../sources/domain/photo_item.dart';
import '../../../sources/domain/photo_source.dart';
import '../../domain/slideshow_config.dart';

/// Why a slide could not be shown, as reported to [SlideRenderer.onUnavailable].
enum SlideUnavailableReason {
  /// The photo is fine, but its screen-sized copy is not prepared yet (only
  /// checked small copies are shown). It should be tried again later.
  notPreparedYet,

  /// The photo could not be fetched from its source (file removed, share
  /// offline, ...).
  unreadable,
}

/// Renders one [PhotoItem] according to the configured [DisplayMode].
///
/// Fetches the real image bytes via `source.fetchToCache(item)` and decodes
/// them with `Image.file`. Bug found on a real device: earlier versions of
/// this widget never fetched anything at all - `SlideshowEngine` only ever
/// tracked item *metadata*, so every configured real source (local folder,
/// SMB, Nextcloud) rendered nothing but a filename-labelled placeholder box,
/// identical to how `MockPhotoSource`'s non-decodable placeholder bytes were
/// (correctly) handled. Now: a genuinely undecodable file (still
/// `MockPhotoSource`'s test bytes, a corrupt file, or a HEIC/format Flutter's
/// codec can't decode) falls back to the same placeholder box via
/// `Image.file`'s `errorBuilder`, instead of that being the *only* code path.
class SlideRenderer extends ConsumerStatefulWidget {
  const SlideRenderer({
    super.key,
    required this.item,
    required this.source,
    required this.displayMode,
    this.onUnavailable,
  });

  /// Called when the photo cannot be shown, so the slideshow can skip it. Not
  /// called for a result that arrives after the widget has moved on to another
  /// item.
  final ValueChanged<SlideUnavailableReason>? onUnavailable;

  final PhotoItem item;
  final PhotoSource source;
  final DisplayMode displayMode;

  @override
  ConsumerState<SlideRenderer> createState() => _SlideRendererState();
}

class _SlideRendererState extends ConsumerState<SlideRenderer> {
  Future<File?>? _fileFuture;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SlideRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.sourceId != widget.item.sourceId ||
        oldWidget.item.id != widget.item.id) {
      _load();
    }
  }

  void _load() {
    // No CacheLease/ImageCacheManager wiring yet (see docs/PLAN.md - the
    // persistent prefetch/cache pipeline is a later milestone); this fetches
    // directly, once per displayed item, which is enough to actually show
    // real photos and matches the app's current "resolve on demand" state
    // elsewhere in the engine.
    final requested = widget.item;
    _fileFuture = _resolve().then<File?>((outcome) {
      final file = outcome.result.valueOrNull;
      // A late result for an item that is no longer shown must neither change
      // this slide nor skip the item that is shown now.
      final stillShown = mounted &&
          widget.item.sourceId == requested.sourceId &&
          widget.item.id == requested.id;
      if (file == null && stillShown) {
        final message = outcome.result.failureOrNull?.message;
        _fetchError = message;
        widget.onUnavailable?.call(outcome.notPreparedYet
            ? SlideUnavailableReason.notPreparedYet
            : SlideUnavailableReason.unreadable);
        debugPrint('Fetch failed for ${requested.id}: $message');
      }
      return file;
    }).catchError((Object e) {
      debugPrint('Fetch threw for ${requested.id}: $e');
      return null;
    });
    // Trigger a rebuild once the fetch resolves even if didUpdateWidget's
    // caller doesn't naturally call setState again.
    _fileFuture!.whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  /// A prepared small file wins over a fresh download (see SmallPhotoCache).
  Future<({Result<File> result, bool notPreparedYet})> _resolve() async {
    // The file is checked again every time before it is shown; a damaged one
    // is deleted and prepared again.
    final cache = ref.read(smallPhotoCacheProvider);
    final hadFile = await cache.existing(widget.item) != null;
    final small = await cache.verifiedExisting(widget.item);
    if (small != null) {
      return (result: Result<File>.ok(small), notPreparedYet: false);
    }
    // Wait for the settings instead of reading `.value`, which is still null on
    // the first frame and would wrongly fall back to the default.
    final settings = await ref
        .read(settingsProvider.future)
        .catchError((Object _) => const AppSettings());
    // A photo that cannot be scaled never gets a small copy: its original is
    // shown instead, and it is not prepared again.
    final notConvertible = await ref
        .read(notConvertibleStoreProvider)
        .contains(widget.item.stableId);
    // Re-preparing a damaged copy is a preparation job, so it is skipped while
    // preparation is off.
    if (hadFile && settings.preparationEnabled && !notConvertible) {
      unawaited(ref
          .read(smallPhotoWorkerProvider.notifier)
          .reprepare(widget.item, widget.source)
          .then<void>((_) {}, onError: (Object _) {}));
    }
    // Raw downloads can be damaged (truncated or garbled), so by default only
    // checked small copies are shown; the photo is skipped until one exists.
    // With preparation off, the raw download is shown instead.
    if (settings.onlyPreparedRuleActive && !notConvertible) {
      return (
        result: Result<File>.err(
            const NotFound('Verkleinerte Kopie noch nicht fertig')),
        notPreparedYet: true,
      );
    }
    // The raw download is the original file, so it must be complete: a
    // truncated one would decode only partly (the rest is garbage on screen).
    // It is checked with the same rule as the small copies, against the size
    // the source reported. A photo without that proof is never shown.
    final fetched = await widget.source.fetchToCache(widget.item);
    final file = fetched.valueOrNull;
    if (file == null) {
      return (result: fetched, notPreparedYet: false);
    }
    final complete = await SmallPhotoCache.looksComplete(
      file,
      widget.item.size,
      downloadIsOriginal: true,
    );
    if (!complete) {
      await cache.deleteIfTemp(file);
      return (
        result: Result<File>.err(
            const NetworkError('Heruntergeladene Datei ist unvollständig')),
        notPreparedYet: false,
      );
    }
    return (result: fetched, notPreparedYet: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _fileFuture,
      builder: (context, snapshot) {
        final file = snapshot.data;
        switch (widget.displayMode) {
          case DisplayMode.contain:
            // The photo fits the whole screen. The real aspect ratio is not
            // used as a box: the index does not store it, so a fixed 16:9 box
            // cut portrait and 4:3 photos down to a fraction of the screen.
            return SizedBox.expand(
              child: _PhotoImage(
                  item: widget.item, file: file, fit: BoxFit.contain),
            );
          case DisplayMode.cover:
            return SizedBox.expand(
              child: _PhotoImage(
                  item: widget.item,
                  file: file,
                  error: _fetchError,
                  fit: BoxFit.cover),
            );
          case DisplayMode.blurredBackdrop:
            return Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: _PhotoImage(
                      item: widget.item, file: file, fit: BoxFit.cover),
                ),
                // The foreground fills the whole screen; BoxFit.contain scales
                // the photo to the largest size that fits and keeps its aspect
                // ratio. A fixed box would shrink it to the photo's ratio.
                SizedBox.expand(
                  child: _PhotoImage(
                      item: widget.item, file: file, fit: BoxFit.contain),
                ),
              ],
            );
        }
      },
    );
  }
}

/// Renders [file] via `Image.file` when available and decodable; otherwise
/// (still loading, fetch failed, or the codec can't decode the bytes) falls
/// back to a deterministic placeholder box so the slideshow never shows a
/// hard error or a blank frame.
class _PhotoImage extends StatelessWidget {
  const _PhotoImage({
    required this.item,
    required this.file,
    required this.fit,
    this.error,
  });

  final String? error;

  final PhotoItem item;
  final File? file;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return _PlaceholderBox(item: item, reason: error);
    }
    // Decode at screen resolution instead of full camera size: a 12 MP photo
    // otherwise takes ~48 MB of memory on the frame. A portrait photo is
    // limited by the screen height, so it is decoded to that size instead of
    // the width; otherwise it would be enlarged (and blurred) when shown.
    final screen = MediaQuery.sizeOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final portrait = _isPortrait(item);
    final l10n = AppLocalizations.of(context);
    return Image.file(
      file!,
      fit: fit,
      cacheWidth: portrait ? null : (screen.width * devicePixelRatio).round(),
      cacheHeight: portrait ? (screen.height * devicePixelRatio).round() : null,
      errorBuilder: (context, err, stackTrace) => _PlaceholderBox(
        item: item,
        // The raw exception is only useful while developing; on the frame
        // only the translated reason is shown.
        reason: kDebugMode
            ? '${l10n.slideDecodeFailed}: $err'
            : l10n.slideDecodeFailed,
      ),
    );
  }
}

/// Whether the photo is shown upright in portrait orientation. The stored size
/// is the sensor size; EXIF orientations 5 to 8 rotate it by 90 degrees.
/// Unknown sizes count as landscape.
bool _isPortrait(PhotoItem item) {
  final w = item.width, h = item.height;
  if (w == null || h == null) return false;
  final rotated = item.orientation >= 5 && item.orientation <= 8;
  return rotated ? w > h : h > w;
}

/// Deterministic placeholder (color derived from the item id, plus its
/// filename) shown whenever the real photo isn't available/decodable yet.
class _PlaceholderBox extends StatelessWidget {
  const _PlaceholderBox({required this.item, this.reason});

  final String? reason;

  final PhotoItem item;

  @override
  Widget build(BuildContext context) {
    final hue = (item.id.hashCode % 360).abs().toDouble();
    final color = HSVColor.fromAHSV(1, hue, 0.45, 0.55).toColor();
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, color: Colors.white70, size: 48),
          const SizedBox(height: 8),
          Text(item.name, style: const TextStyle(color: Colors.white70)),
          if (reason != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(reason!,
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
