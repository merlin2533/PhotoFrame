import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:test/test.dart';

void main() {
  group('Rotation settings', () {
    test('defaults are a daily swap of 5 percent and a 7 day renewal', () {
      const settings = AppSettings();
      expect(settings.rotationSwapPercent, 5);
      expect(settings.rotationRenewalDays, 7);
    });

    test('the values survive a JSON round trip', () {
      final settings = const AppSettings()
          .copyWith(rotationSwapPercent: 35, rotationRenewalDays: 12);
      final back = AppSettings.fromJson(settings.toJson());
      expect(back.rotationSwapPercent, 35);
      expect(back.rotationRenewalDays, 12);
    });

    test('0 percent (no daily swap) survives a JSON round trip', () {
      final settings = const AppSettings().copyWith(rotationSwapPercent: 0);
      final back = AppSettings.fromJson(settings.toJson());
      expect(back.rotationSwapPercent, 0);
    });

    test('the defaults are written and read back unchanged', () {
      final back = AppSettings.fromJson(const AppSettings().toJson());
      expect(back.rotationSwapPercent, 5);
      expect(back.rotationRenewalDays, 7);
    });

    test('a missing swap percent falls back to the default of 5', () {
      final json = const AppSettings().toJson()..remove('rotationSwapPercent');
      expect(AppSettings.fromJson(json).rotationSwapPercent, 5);
    });
  });
}
