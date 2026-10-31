import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/index/photo_index_store.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';

void main() {
  test('save and load round-trip keeps all fields', () async {
    String? stored;
    final store = PhotoIndexStore(
      read: () async => stored,
      write: (json) async => stored = json,
    );
    final items = [
      PhotoItem(
        id: 'Urlaub/a.jpg',
        sourceId: 's1',
        folderId: 'Urlaub',
        name: 'a.jpg',
        mediaType: MediaType.image,
        size: 1234,
        mtime: DateTime.fromMillisecondsSinceEpoch(1000),
        width: 4000,
        height: 3000,
        takenAt: DateTime.fromMillisecondsSinceEpoch(2000),
        orientation: 6,
      ),
      PhotoItem(
        id: 'b.png',
        sourceId: 's2',
        folderId: '',
        name: 'b.png',
        mediaType: MediaType.image,
        size: 1,
        mtime: DateTime.fromMillisecondsSinceEpoch(3000),
      ),
    ];
    await store.save(items);
    final snapshot = await store.load();
    final loaded = snapshot.items;
    expect(loaded.length, 2);
    expect(loaded[0].id, 'Urlaub/a.jpg');
    expect(loaded[0].width, 4000);
    expect(loaded[0].takenAt, DateTime.fromMillisecondsSinceEpoch(2000));
    expect(loaded[0].orientation, 6);
    expect(loaded[1].takenAt, isNull);
  });

  test('clear makes the index count as empty and stale', () async {
    String? stored;
    final store = PhotoIndexStore(
      read: () async => stored,
      write: (json) async => stored = json,
    );
    await store.clear();
    final snapshot = await store.load();
    expect(snapshot.items, isEmpty);
    expect(snapshot.savedAt.millisecondsSinceEpoch, 0);
  });

  test('missing or corrupt index loads as empty', () async {
    final missing =
        PhotoIndexStore(read: () async => null, write: (_) async {});
    expect((await missing.load()).items, isEmpty);
    final corrupt =
        PhotoIndexStore(read: () async => '{not json', write: (_) async {});
    expect((await corrupt.load()).items, isEmpty);
  });
}
