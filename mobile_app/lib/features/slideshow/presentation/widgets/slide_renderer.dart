import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../sources/domain/photo_item.dart';
import '../../domain/slideshow_config.dart';

/// Renders one [PhotoItem] according to the configured [DisplayMode].
///
/// TEST-DATA LIMITATION (documented per task instructions): `MockPhotoSource`
/// (the only real `PhotoSource` available while `SmbPhotoSource`/
/// `NextcloudPhotoSource`/`LocalFolderSource` are being built by a parallel
/// agent) writes a tiny deterministic non-image byte payload for
/// `fetchToCache`, not a decodable JPEG - so `Image.file` cannot render it.
/// This renderer therefore depicts each item with a deterministic
/// placeholder box (color derived from the item id, plus its name) instead
/// of a real decoded photo. The three [DisplayMode] values are implemented
/// as real, distinct layouts against that placeholder (aspect-ratio-boxed
/// vs. full-bleed vs. blurred backdrop) so the layout logic itself is
/// exercised and visibly different, even though the pixels within are a
/// placeholder rather than a real photo. Swapping in real decodable files
/// later needs no change to the layout logic here - only [_PlaceholderImage]
/// needs replacing with `Image.file(file, fit: ...)` once a real source's
/// cached [File] is available.
class SlideRenderer extends StatelessWidget {
  const SlideRenderer({
    super.key,
    required this.item,
    required this.displayMode,
  });

  final PhotoItem item;
  final DisplayMode displayMode;

  @override
  Widget build(BuildContext context) {
    switch (displayMode) {
      case DisplayMode.contain:
        return Center(
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: _PlaceholderImage(item: item),
          ),
        );
      case DisplayMode.cover:
        return SizedBox.expand(child: _PlaceholderImage(item: item));
      case DisplayMode.blurredBackdrop:
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: _PlaceholderImage(item: item),
            ),
            Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: _PlaceholderImage(item: item),
              ),
            ),
          ],
        );
    }
  }

  double get _aspectRatio {
    final w = item.width;
    final h = item.height;
    if (w == null || h == null || h == 0) return 16 / 9;
    return w / h;
  }
}

/// See [SlideRenderer] doc comment - the placeholder "photo" seam meant to
/// be swapped for `Image.file(...)` once a real, decodable [PhotoItem]'s
/// cached file is available.
class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage({required this.item});

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
        ],
      ),
    );
  }
}
