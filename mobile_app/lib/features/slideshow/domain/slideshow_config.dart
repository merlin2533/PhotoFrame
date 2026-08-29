/// How images are fitted/arranged on screen. Placeholder set of values;
/// expected to grow once real rendering is implemented (e.g. collage modes,
/// Ken Burns effect).
enum DisplayMode {
  /// Fit the whole image inside the screen, letterboxing if needed.
  contain,

  /// Fill the screen, cropping the image as needed.
  cover,

  /// Blur the current image and use it as a backdrop behind a `contain`
  /// rendering of itself (avoids hard letterbox bars).
  blurredBackdrop,
}

/// User-configurable slideshow behaviour.
class SlideshowConfig {
  const SlideshowConfig({
    this.interval = const Duration(seconds: 10),
    this.displayMode = DisplayMode.contain,
    this.showClock = true,
    this.showSourceLabel = false,
    this.noRepeatWindow = 5,
    this.transitionDuration = const Duration(milliseconds: 600),
  });

  /// How long each item stays on screen before advancing.
  final Duration interval;

  final DisplayMode displayMode;

  /// Whether to overlay a clock on the slideshow.
  final bool showClock;

  /// Whether to overlay a small label naming the source an item came from.
  final bool showSourceLabel;

  /// Forwarded to `ShuffleBag.noRepeatWindow` - how many recent items must
  /// not repeat.
  final int noRepeatWindow;

  /// Duration of the crossfade/transition animation between items.
  final Duration transitionDuration;

  SlideshowConfig copyWith({
    Duration? interval,
    DisplayMode? displayMode,
    bool? showClock,
    bool? showSourceLabel,
    int? noRepeatWindow,
    Duration? transitionDuration,
  }) {
    return SlideshowConfig(
      interval: interval ?? this.interval,
      displayMode: displayMode ?? this.displayMode,
      showClock: showClock ?? this.showClock,
      showSourceLabel: showSourceLabel ?? this.showSourceLabel,
      noRepeatWindow: noRepeatWindow ?? this.noRepeatWindow,
      transitionDuration: transitionDuration ?? this.transitionDuration,
    );
  }
}
