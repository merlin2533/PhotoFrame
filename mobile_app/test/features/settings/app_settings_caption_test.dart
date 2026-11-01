import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';

void main() {
  group('AppSettings.showCaptionOverlay', () {
    test('defaults to false', () {
      expect(const AppSettings().showCaptionOverlay, isFalse);
    });

    test('copyWith changes only that field', () {
      const base = AppSettings(intervalSeconds: 20);
      final updated = base.copyWith(showCaptionOverlay: true);
      expect(updated.showCaptionOverlay, isTrue);
      expect(updated.intervalSeconds, 20);
    });

    test('round-trips through toJson/fromJson', () {
      const settings = AppSettings(showCaptionOverlay: true);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.showCaptionOverlay, isTrue);
    });

    test('fromJson defaults to false when missing from an older blob', () {
      final restored = AppSettings.fromJson({'intervalSeconds': 15});
      expect(restored.showCaptionOverlay, isFalse);
    });
  });
}
