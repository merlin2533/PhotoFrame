import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_app/features/pairing/domain/key_fingerprint.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('KeyFingerprintStore', () {
    late _MockSecureStorage storage;
    late KeyFingerprintStore fingerprintStore;
    late Map<String, String> backing;

    setUp(() {
      storage = _MockSecureStorage();
      backing = {};

      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async => backing[invocation.namedArguments[#key] as String],
      );
      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer(
        (invocation) async {
          final key = invocation.namedArguments[#key] as String;
          final value = invocation.namedArguments[#value] as String?;
          if (value == null) {
            backing.remove(key);
          } else {
            backing[key] = value;
          }
        },
      );
      when(() => storage.delete(key: any(named: 'key'))).thenAnswer(
        (invocation) async {
          backing.remove(invocation.namedArguments[#key] as String);
        },
      );

      fingerprintStore = KeyFingerprintStore(storage: storage);
    });

    test('first contact with a frame trusts and stores the fingerprint', () async {
      final result = await fingerprintStore.checkOrTrust('frame-1', 'ABCD1234');
      expect(result, FingerprintTrust.trusted);
      expect(await fingerprintStore.trustedFingerprintFor('frame-1'), 'ABCD1234');
    });

    test('same fingerprint on a known frame reports match without rewriting storage', () async {
      await fingerprintStore.checkOrTrust('frame-1', 'ABCD1234');
      final result = await fingerprintStore.checkOrTrust('frame-1', 'ABCD1234');
      expect(result, FingerprintTrust.match);
      expect(await fingerprintStore.trustedFingerprintFor('frame-1'), 'ABCD1234');
    });

    test('a different fingerprint on a known frame reports mismatch and does not overwrite', () async {
      await fingerprintStore.checkOrTrust('frame-1', 'ABCD1234');
      final result = await fingerprintStore.checkOrTrust('frame-1', 'ZZZZ9999');
      expect(result, FingerprintTrust.mismatch);
      // Must not silently adopt the new fingerprint - only acceptFingerprint may.
      expect(await fingerprintStore.trustedFingerprintFor('frame-1'), 'ABCD1234');
    });

    test('acceptFingerprint explicitly overwrites a mismatched fingerprint', () async {
      await fingerprintStore.checkOrTrust('frame-1', 'ABCD1234');
      await fingerprintStore.checkOrTrust('frame-1', 'ZZZZ9999');
      await fingerprintStore.acceptFingerprint('frame-1', 'ZZZZ9999');
      expect(await fingerprintStore.trustedFingerprintFor('frame-1'), 'ZZZZ9999');

      final result = await fingerprintStore.checkOrTrust('frame-1', 'ZZZZ9999');
      expect(result, FingerprintTrust.match);
    });

    test('different frame ids are tracked independently', () async {
      await fingerprintStore.checkOrTrust('frame-1', 'AAAA1111');
      await fingerprintStore.checkOrTrust('frame-2', 'BBBB2222');

      expect(await fingerprintStore.checkOrTrust('frame-1', 'AAAA1111'), FingerprintTrust.match);
      expect(await fingerprintStore.checkOrTrust('frame-2', 'BBBB2222'), FingerprintTrust.match);
      expect(await fingerprintStore.checkOrTrust('frame-2', 'AAAA1111'), FingerprintTrust.mismatch);
    });

    test('forget removes the trusted fingerprint for a frame', () async {
      await fingerprintStore.checkOrTrust('frame-1', 'AAAA1111');
      await fingerprintStore.forget('frame-1');
      expect(await fingerprintStore.trustedFingerprintFor('frame-1'), isNull);
      expect(await fingerprintStore.checkOrTrust('frame-1', 'AAAA1111'), FingerprintTrust.trusted);
    });

    test('checkOrTrust rejects an empty fingerprint', () {
      expect(() => fingerprintStore.checkOrTrust('frame-1', ''), throwsArgumentError);
    });

    test('fingerprintMismatchWarningFor fills in the frame label', () {
      final warning = fingerprintMismatchWarningFor('Wohnzimmer-Frame');
      expect(warning, contains('Wohnzimmer-Frame'));
      expect(warning, contains('Wiederherstellung'));
    });
  });
}
