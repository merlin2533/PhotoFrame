import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/index/photo_index_store.dart';

void main() {
  test('a truncated index file loads as empty and is cleared', () async {
    // Simulates a write cut off by a crash.
    String? stored = '{"savedAt": 1700000000000, "items": [{"id": "a';
    final store = PhotoIndexStore(
      read: () async => stored,
      write: (json) async => stored = json,
    );

    final snapshot = await store.load();

    expect(snapshot.items, isEmpty);
    expect(snapshot.savedAt, DateTime.fromMillisecondsSinceEpoch(0));
    // The damaged file was replaced, so the next load is clean.
    expect(stored, contains('"items":[]'));
    final reloaded = await store.load();
    expect(reloaded.items, isEmpty);
  });

  test('a read failure keeps the file untouched', () async {
    var writes = 0;
    final store = PhotoIndexStore(
      read: () async => throw StateError('disk unavailable'),
      write: (_) async => writes++,
    );

    final snapshot = await store.load();

    expect(snapshot.items, isEmpty);
    expect(writes, 0);
  });
}
