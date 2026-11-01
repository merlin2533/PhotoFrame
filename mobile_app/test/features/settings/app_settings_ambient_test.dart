import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';

void main() {
  group('AppSettings ambient dimming', () {
    test('defaults: disabled, window 22:00-06:00', () {
      const s = AppSettings();
      expect(s.ambientDimEnabled, isFalse);
      expect(s.dimStartMinutes, 22 * 60);
      expect(s.dimEndMinutes, 6 * 60);
    });

    test('copyWith changes only the ambient fields', () {
      const base = AppSettings(intervalSeconds: 20);
      final updated = base.copyWith(
        ambientDimEnabled: true,
        dimStartMinutes: 23 * 60,
        dimEndMinutes: 7 * 60 + 30,
      );
      expect(updated.ambientDimEnabled, isTrue);
      expect(updated.dimStartMinutes, 23 * 60);
      expect(updated.dimEndMinutes, 7 * 60 + 30);
      expect(updated.intervalSeconds, 20);
    });

    test('round-trips through toJson/fromJson', () {
      const s = AppSettings(
        ambientDimEnabled: true,
        dimStartMinutes: 21 * 60 + 15,
        dimEndMinutes: 5 * 60 + 45,
      );
      final restored = AppSettings.fromJson(s.toJson());
      expect(restored.ambientDimEnabled, isTrue);
      expect(restored.dimStartMinutes, 21 * 60 + 15);
      expect(restored.dimEndMinutes, 5 * 60 + 45);
    });

    test('fromJson defaults when missing from an older blob', () {
      final restored = AppSettings.fromJson({'intervalSeconds': 15});
      expect(restored.ambientDimEnabled, isFalse);
      expect(restored.dimStartMinutes, 22 * 60);
      expect(restored.dimEndMinutes, 6 * 60);
    });
  });
}
