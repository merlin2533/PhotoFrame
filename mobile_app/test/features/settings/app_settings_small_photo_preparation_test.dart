import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';

void main() {
  group('AppSettings.smallPhotoPreparation', () {
    test('defaults to true', () {
      expect(const AppSettings().smallPhotoPreparation, isTrue);
      expect(const AppSettings().preparationEnabled, isTrue);
    });

    test('defaults to true when the key is missing from stored JSON', () {
      final settings = AppSettings.fromJson(const <String, dynamic>{});
      expect(settings.smallPhotoPreparation, isTrue);
    });

    test('survives a JSON round trip with the default true', () {
      final json = const AppSettings().toJson();
      expect(json['smallPhotoPreparation'], isTrue);
      final restored = AppSettings.fromJson(json);
      expect(restored.smallPhotoPreparation, isTrue);
      expect(restored.preparationEnabled, isTrue);
    });

    test('survives a JSON round trip when switched off', () {
      final json =
          const AppSettings().copyWith(smallPhotoPreparation: false).toJson();
      expect(json['smallPhotoPreparation'], isFalse);
      final restored = AppSettings.fromJson(json);
      expect(restored.smallPhotoPreparation, isFalse);
      expect(restored.preparationEnabled, isFalse);
    });

    test('switching off does not change onlyPreparedPhotos', () {
      final off = const AppSettings().copyWith(smallPhotoPreparation: false);
      expect(off.onlyPreparedPhotos, isTrue);
      expect(off.onlyPreparedRuleActive, isFalse);
      expect(const AppSettings().onlyPreparedRuleActive, isTrue);
      expect(off.toJson()['onlyPreparedPhotos'], isTrue);
    });
  });
}
