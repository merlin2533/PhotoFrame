import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared flag: `true` while the slideshow is changing slides or decoding the
/// photo it shows. The small-photo worker checks it before it starts a scaling
/// job, so background decoding never competes with the slideshow.
///
/// The slideshow screen sets it to `true` when a slide changes and clears it
/// one frame after the change plus a short hold (see `_markSlideChange` in
/// `slideshow_screen.dart`). Downloads do not look at this flag: they are I/O.
///
/// This is a plain object and not a Riverpod state on purpose: the screen
/// clears it in `dispose`, where a provider must not be written and whose ref
/// may already be gone.
class SlideshowBusyFlag {
  /// Whether the slideshow is busy right now.
  bool busy = false;
}

/// The one [SlideshowBusyFlag] of the app.
final Provider<SlideshowBusyFlag> slideshowBusyProvider =
    Provider<SlideshowBusyFlag>((ref) => SlideshowBusyFlag());
