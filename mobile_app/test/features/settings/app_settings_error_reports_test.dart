import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';

void main() {
  group('AppSettings.sendErrorReports', () {
    test('defaults to true', () {
      expect(const AppSettings().sendErrorReports, isTrue);
    });

    test('defaults to true when the key is missing from stored JSON', () {
      final settings = AppSettings.fromJson(const <String, dynamic>{});
      expect(settings.sendErrorReports, isTrue);
    });

    test('survives a JSON round trip when switched off', () {
      final restored = AppSettings.fromJson(
        const AppSettings(sendErrorReports: false).toJson(),
      );
      expect(restored.sendErrorReports, isFalse);
    });

    test('survives a JSON round trip when switched on', () {
      final json = const AppSettings().toJson();
      expect(json['sendErrorReports'], isTrue);
      expect(AppSettings.fromJson(json).sendErrorReports, isTrue);
    });

    test('copyWith changes only the switch', () {
      final changed = const AppSettings().copyWith(sendErrorReports: false);
      expect(changed.sendErrorReports, isFalse);
      expect(changed.copyWith().sendErrorReports, isFalse);
    });
  });
}
