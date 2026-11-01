import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:test/test.dart';

void main() {
  group('Rotation settings', () {
    test('defaults are a daily swap of 10 percent and a 7 day renewal', () {
      const settings = AppSettings();
      expect(settings.rotationSwapPercent, 10);
      expect(settings.rotationRenewalDays, 7);
    });

    test('the values survive a JSON round trip', () {
      final settings = const AppSettings()
          .copyWith(rotationSwapPercent: 35, rotationRenewalDays: 12);
      final back = AppSettings.fromJson(settings.toJson());
      expect(back.rotationSwapPercent, 35);
      expect(back.rotationRenewalDays, 12);
    });

    test('the defaults are written and read back unchanged', () {
      final back = AppSettings.fromJson(const AppSettings().toJson());
      expect(back.rotationSwapPercent, 10);
      expect(back.rotationRenewalDays, 7);
    });
  });
}
