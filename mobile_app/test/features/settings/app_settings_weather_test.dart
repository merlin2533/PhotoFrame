import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';

void main() {
  group('AppSettings weather fields', () {
    test('default to disabled/unset', () {
      const settings = AppSettings();
      expect(settings.weatherEnabled, isFalse);
      expect(settings.weatherLatitude, isNull);
      expect(settings.weatherLongitude, isNull);
      expect(settings.weatherLocationLabel, isNull);
    });

    test('copyWith sets weather fields additively without touching others', () {
      const base = AppSettings(intervalSeconds: 20, showClock: false);
      final updated = base.copyWith(
        weatherEnabled: true,
        weatherLatitude: 52.52,
        weatherLongitude: 13.405,
        weatherLocationLabel: 'Berlin, Deutschland',
      );
      expect(updated.weatherEnabled, isTrue);
      expect(updated.weatherLatitude, 52.52);
      expect(updated.weatherLongitude, 13.405);
      expect(updated.weatherLocationLabel, 'Berlin, Deutschland');
      // Untouched fields survive copyWith.
      expect(updated.intervalSeconds, 20);
      expect(updated.showClock, isFalse);
    });

    test('clearWeatherLocation resets lat/lon/label to null', () {
      const base = AppSettings(
        weatherEnabled: true,
        weatherLatitude: 1.0,
        weatherLongitude: 2.0,
        weatherLocationLabel: 'Somewhere',
      );
      final cleared = base.copyWith(clearWeatherLocation: true);
      expect(cleared.weatherLatitude, isNull);
      expect(cleared.weatherLongitude, isNull);
      expect(cleared.weatherLocationLabel, isNull);
      // weatherEnabled is independent of the location fields.
      expect(cleared.weatherEnabled, isTrue);
    });

    test('round-trips through toJson/fromJson', () {
      const settings = AppSettings(
        weatherEnabled: true,
        weatherLatitude: 48.13,
        weatherLongitude: 11.58,
        weatherLocationLabel: 'München, Bayern, Deutschland',
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.weatherEnabled, isTrue);
      expect(restored.weatherLatitude, 48.13);
      expect(restored.weatherLongitude, 11.58);
      expect(restored.weatherLocationLabel, 'München, Bayern, Deutschland');
    });

    test('fromJson defaults weather fields when missing from an older persisted blob', () {
      final restored = AppSettings.fromJson({'intervalSeconds': 15});
      expect(restored.weatherEnabled, isFalse);
      expect(restored.weatherLatitude, isNull);
      expect(restored.weatherLongitude, isNull);
      expect(restored.weatherLocationLabel, isNull);
    });
  });
}
