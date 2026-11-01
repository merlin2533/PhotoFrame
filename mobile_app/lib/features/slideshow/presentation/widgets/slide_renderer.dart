import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../cache/small_photo_cache.dart';
import '../../../sources/domain/photo_item.dart';
import '../../../sources/domain/photo_source.dart';
import '../../domain/slideshow_config.dart';

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

  /// Called when the photo cannot be fetched, so the slideshow can skip it.
  final VoidCallback? onUnavailable;

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
    _fileFuture = _resolve().then((result) {
      if (result.valueOrNull == null) {
        _fetchError = result.failureOrNull?.message;
        widget.onUnavailable?.call();
        debugPrint(
            'Fetch failed for ${widget.item.id}: ${result.failureOrNull?.message}');
      }
      return result.valueOrNull;
    }).catchError((Object e) {
      debugPrint('Fetch threw for ${widget.item.id}: $e');
      return null;
    });
    // Trigger a rebuild once the fetch resolves even if didUpdateWidget's
    // caller doesn't naturally call setState again.
    _fileFuture!.whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  /// A prepared small file wins over a fresh download (see SmallPhotoCache).
  Future<Result<File>> _resolve() async {
    final small = await ref.read(smallPhotoCacheProvider).existing(widget.item);
    if (small != null) return Result.ok(small);
    return widget.source.fetchToCache(widget.item);
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
                Center(
                  child: AspectRatio(
                    aspectRatio: _aspectRatio,
                    child: _PhotoImage(
                        item: widget.item, file: file, fit: BoxFit.contain),
                  ),
                ),
              ],
            );
        }
      },
    );
  }

  double get _aspectRatio {
    final w = widget.item.width;
    final h = widget.item.height;
    if (w == null || h == null || h == 0) return 16 / 9;
    return w / h;
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
    // otherwise takes ~48 MB of memory on the frame.
    final screenWidth = MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    final l10n = AppLocalizations.of(context);
    return Image.file(
      file!,
      fit: fit,
      cacheWidth: screenWidth.round(),
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
