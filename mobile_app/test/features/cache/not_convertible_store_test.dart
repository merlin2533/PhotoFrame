import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/not_convertible_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('marked photos are persisted and read back by a new store', () async {
    final first = NotConvertibleStore(prefs: SharedPreferences.getInstance);
    expect(await first.contains('src:0123456789abcdef'), isFalse);

    await first.add('src:0123456789abcdef');
    await first.add('src:0123456789abcdef');
    await first.add('src:fedcba9876543210');

    // A new store has no memory of the first one: it reads the preferences.
    final second = NotConvertibleStore(prefs: SharedPreferences.getInstance);
    expect(await second.contains('src:0123456789abcdef'), isTrue);
    expect(await second.contains('src:fedcba9876543210'), isTrue);
    expect(await second.contains('src:other'), isFalse);
    expect(await second.load(), {
      'src:0123456789abcdef',
      'src:fedcba9876543210',
    });

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(NotConvertibleStore.prefsKey),
      ['src:0123456789abcdef', 'src:fedcba9876543210'],
    );
  });

  test('a store that cannot read the preferences marks nothing and keeps going',
      () async {
    final broken = NotConvertibleStore(
      prefs: () => Future<SharedPreferences>.error(StateError('no prefs')),
    );

    expect(await broken.contains('src:x'), isFalse);
    await broken.add('src:x');
    expect(await broken.contains('src:x'), isFalse);
  });
}
