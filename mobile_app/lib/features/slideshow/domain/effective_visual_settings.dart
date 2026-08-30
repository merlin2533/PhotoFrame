import '../../settings/domain/app_settings.dart';

/// The transition/Ken-Burns behaviour that should actually be applied for
/// one frame of the slideshow, after folding in the "Bewegung reduzieren"
/// (reduce motion) accessibility signal.
///
/// Kept as a small, pure, widget-free value type specifically so the
/// interaction between `AppSettings.transition`/`AppSettings.kenBurnsEnabled`
/// and `MediaQuery.disableAnimations` can be unit-tested without pumping a
/// widget tree (see `test/features/slideshow/effective_visual_settings_test.dart`).
class EffectiveVisualSettings {
  const EffectiveVisualSettings({
    required this.transition,
    required this.kenBurnsEnabled,
  });

  final SlideshowTransition transition;
  final bool kenBurnsEnabled;

  /// Resolves the effective transition/Ken-Burns settings for one frame.
  ///
  /// When [reduceMotion] is true (the platform's "reduce motion"
  /// accessibility signal, surfaced in Flutter as
  /// `MediaQuery.of(context).disableAnimations`), the transition is forced
  /// to [SlideshowTransition.none] and Ken Burns is forced off, regardless
  /// of what the user configured - motion-sensitive users must not see
  /// slide/fade transitions or the Ken Burns zoom/pan even if they once
  /// enabled it before turning the system setting on.
  factory EffectiveVisualSettings.resolve({
    required SlideshowTransition transition,
    required bool kenBurnsEnabled,
    required bool reduceMotion,
  }) {
    if (reduceMotion) {
      return const EffectiveVisualSettings(
        transition: SlideshowTransition.none,
        kenBurnsEnabled: false,
      );
    }
    return EffectiveVisualSettings(
      transition: transition,
      kenBurnsEnabled: kenBurnsEnabled,
    );
  }

  /// Convenience overload resolving directly from [settings].
  factory EffectiveVisualSettings.fromSettings(
    AppSettings settings, {
    required bool reduceMotion,
  }) {
    return EffectiveVisualSettings.resolve(
      transition: settings.transition,
      kenBurnsEnabled: settings.kenBurnsEnabled,
      reduceMotion: reduceMotion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EffectiveVisualSettings &&
      other.transition == transition &&
      other.kenBurnsEnabled == kenBurnsEnabled;

  @override
  int get hashCode => Object.hash(transition, kenBurnsEnabled);

  @override
  String toString() =>
      'EffectiveVisualSettings(transition: $transition, kenBurnsEnabled: $kenBurnsEnabled)';
}
