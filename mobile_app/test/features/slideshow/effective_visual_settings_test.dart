import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/slideshow/domain/effective_visual_settings.dart';

void main() {
  group('EffectiveVisualSettings.resolve', () {
    test('passes through the configured transition/Ken Burns when reduceMotion is false', () {
      final effective = EffectiveVisualSettings.resolve(
        transition: SlideshowTransition.slide,
        kenBurnsEnabled: true,
        reduceMotion: false,
      );
      expect(effective.transition, SlideshowTransition.slide);
      expect(effective.kenBurnsEnabled, isTrue);
    });

    test('forces transition=none and Ken Burns off when reduceMotion is true, even if both are configured on', () {
      final effective = EffectiveVisualSettings.resolve(
        transition: SlideshowTransition.slide,
        kenBurnsEnabled: true,
        reduceMotion: true,
      );
      expect(effective.transition, SlideshowTransition.none);
      expect(effective.kenBurnsEnabled, isFalse);
    });

    test('fade transition is also overridden to none under reduceMotion', () {
      final effective = EffectiveVisualSettings.resolve(
        transition: SlideshowTransition.fade,
        kenBurnsEnabled: false,
        reduceMotion: true,
      );
      expect(effective.transition, SlideshowTransition.none);
      expect(effective.kenBurnsEnabled, isFalse);
    });

    test('leaves transition=none as none regardless of reduceMotion', () {
      for (final reduceMotion in [true, false]) {
        final effective = EffectiveVisualSettings.resolve(
          transition: SlideshowTransition.none,
          kenBurnsEnabled: false,
          reduceMotion: reduceMotion,
        );
        expect(effective.transition, SlideshowTransition.none);
      }
    });

    test('equality/hashCode are value-based', () {
      const a = EffectiveVisualSettings(transition: SlideshowTransition.fade, kenBurnsEnabled: true);
      const b = EffectiveVisualSettings(transition: SlideshowTransition.fade, kenBurnsEnabled: true);
      const c = EffectiveVisualSettings(transition: SlideshowTransition.none, kenBurnsEnabled: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('EffectiveVisualSettings.fromSettings', () {
    test('resolves directly from an AppSettings instance', () {
      const settings = AppSettings(
        transition: SlideshowTransition.slide,
        kenBurnsEnabled: true,
      );
      final withReduceMotion =
          EffectiveVisualSettings.fromSettings(settings, reduceMotion: true);
      expect(withReduceMotion.transition, SlideshowTransition.none);
      expect(withReduceMotion.kenBurnsEnabled, isFalse);

      final withoutReduceMotion =
          EffectiveVisualSettings.fromSettings(settings, reduceMotion: false);
      expect(withoutReduceMotion.transition, SlideshowTransition.slide);
      expect(withoutReduceMotion.kenBurnsEnabled, isTrue);
    });
  });
}
