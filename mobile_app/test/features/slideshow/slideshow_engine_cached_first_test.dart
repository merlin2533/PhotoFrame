import 'package:mobile_app/features/index/working_set_pool.dart';
import 'package:mobile_app/features/slideshow/domain/slideshow_engine.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:test/test.dart';

/// Builds a pool of [count] photos of one source, with a resolver that finds
/// them by key. Every photo resolves, so only the cache check decides the order.
({InMemoryWorkingSetPool pool, Map<String, PhotoItem> itemsByKey}) _fixture(
    int count) {
  final pool = InMemoryWorkingSetPool(targetSize: count);
  final itemsByKey = <String, PhotoItem>{};
  for (var i = 0; i < count; i++) {
    final item = PhotoItem(
      id: 'folder/photo$i.jpg',
      sourceId: 'src-1',
      folderId: 'folder',
      name: 'photo$i.jpg',
      mediaType: MediaType.image,
      size: 1000 + i,
      mtime: DateTime(2024, 1, 1),
    );
    itemsByKey['${item.sourceId}::${item.id}'] = item;
    pool.add(PoolEntry(
      sourceId: item.sourceId,
      itemId: item.id,
      addedToPoolAt: DateTime(2024, 1, 1),
    ));
  }
  return (pool: pool, itemsByKey: itemsByKey);
}

SlideshowEngine _engine(
  ({InMemoryWorkingSetPool pool, Map<String, PhotoItem> itemsByKey}) f, {
  required bool Function(PoolEntry entry) isCached,
}) =>
    SlideshowEngine(
      pool: f.pool,
      sources: const {},
      resolveItem: (entry) async => f.itemsByKey[entry.key],
      isCached: isCached,
    );

void main() {
  group('SlideshowEngine cached-first selection', () {
    test('skips an uncached photo for a cached one and keeps it in the pool',
        () async {
      final f = _fixture(4);
      // Fixed show order, drawn before start(): the head is not cached.
      final cachedKeys = <String>{};
      final engine = _engine(f, isCached: (e) => cachedKeys.contains(e.key));
      final order = engine.upcomingEntries(4);
      cachedKeys.add(order[2].key);

      await engine.start();

      expect(engine.currentItem?.id, f.itemsByKey[order[2].key]!.id,
          reason: 'the cached photo is shown instead of the uncached head');
      for (var i = 0; i < 3; i++) {
        await engine.skipToNext();
        final shown = engine.currentItem!;
        expect(cachedKeys, contains('${shown.sourceId}::${shown.id}'),
            reason: 'every photo shown while one is cached is cached');
      }
      expect(f.pool.entries.length, 4,
          reason: 'the uncached photos stay in the pool');
      await engine.dispose();
    });

    test('shows the uncached photo when no photo in the pool is cached',
        () async {
      final f = _fixture(4);
      final engine = _engine(f, isCached: (_) => false);
      final order = engine.upcomingEntries(4);

      await engine.start();
      expect(engine.currentItem?.id, f.itemsByKey[order[0].key]!.id,
          reason: 'with nothing cached the order is unchanged (wait/fetch)');

      await engine.skipToNext();
      expect(engine.currentItem?.id, f.itemsByKey[order[1].key]!.id);
      await engine.dispose();
    });

    test('shows a skipped photo once it becomes cached', () async {
      final f = _fixture(4);
      final cachedKeys = <String>{};
      final engine = _engine(f, isCached: (e) => cachedKeys.contains(e.key));
      final order = engine.upcomingEntries(4);
      cachedKeys.add(order[2].key);

      await engine.start();
      expect(engine.currentItem?.id, f.itemsByKey[order[2].key]!.id);

      // The skipped head is cached in the meantime (e.g. by the prefetch).
      cachedKeys.add(order[0].key);
      await engine.skipToNext();
      expect(engine.currentItem?.id, f.itemsByKey[order[0].key]!.id,
          reason: 'the skipped photo comes up once it is on disk');
      await engine.dispose();
    });
  });
}
