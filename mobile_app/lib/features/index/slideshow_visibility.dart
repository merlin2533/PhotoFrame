import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the slideshow screen is currently shown.
///
/// [BackgroundJobs] only crawls sources and prepares photos while this is
/// true. `SlideshowScreen` sets it to true once it is on screen and back to
/// false when it is disposed.
class SlideshowVisibility extends Notifier<bool> {
  @override
  bool build() => false;

  void setVisible(bool visible) {
    // A late call from a screen that is disposed together with the whole
    // provider scope must not touch the disposed provider.
    if (!ref.mounted) return;
    state = visible;
  }
}

final NotifierProvider<SlideshowVisibility, bool> slideshowVisibleProvider =
    NotifierProvider<SlideshowVisibility, bool>(SlideshowVisibility.new);
