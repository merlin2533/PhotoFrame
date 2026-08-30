import 'package:fake_async/fake_async.dart';
import 'package:mobile_app/features/index/working_set_pool.dart';
import 'package:mobile_app/features/slideshow/domain/slideshow_config.dart';
import 'package:mobile_app/features/slideshow/domain/slideshow_engine.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:test/test.dart';

/// Builds a [WorkingSetPool] populated from every item [MockPhotoSource]
/// generates, plus an [ItemResolver] that looks items up by key - the same
/// shape `slideshow_screen.dart` wires up in production, just without the
/// UI/Riverpod layer.
({InMemoryWorkingSetPool pool, Map<String, PhotoItem> itemsByKey, PhotoSource source})
    _buildFixture({int folderCount = 1, int itemsPerFolder = 8}) {
  final source = MockPhotoSource(
    id: 'src-1',
    folderCount: folderCount,
    itemsPerFolder: itemsPerFolder,
    // No artificial delay - keeps fakeAsync flushes trivial. `resolveItem`
    // in these tests is a plain map lookup and doesn't call back into
    // `source` at all; `source` is only used to generate deterministic
    // PhotoItem fixtures.
    simulatedDelay: Duration.zero,
  );
  final pool = InMemoryWorkingSetPool(targetSize: folderCount * itemsPerFolder);
  final itemsByKey = <String, PhotoItem>{};

  // MockPhotoSource's listFolders/listImages are streams with an artificial
  // delay; draining them synchronously here (outside of fakeAsync) is fine
  // since simulatedDelay is Duration.zero and this happens once, before any
  // engine/timer is created.
  return (pool: pool, itemsByKey: itemsByKey, source: source);
}

Future<void> _populate(
  PhotoSource source,
  InMemoryWorkingSetPool pool,
  Map<String, PhotoItem> itemsByKey,
) async {
  await for (final folderResult in source.listFolders()) {
    final folder = folderResult.valueOrNull;
    if (folder == null) continue;
    await for (final itemResult in source.listImages(folder)) {
      final item = itemResult.valueOrNull;
      if (item == null) continue;
      itemsByKey['${item.sourceId}::${item.id}'] = item;
      pool.add(PoolEntry(
        sourceId: item.sourceId,
        itemId: item.id,
        addedToPoolAt: DateTime.now(),
      ));
    }
  }
}

void main() {
  group('SlideshowEngine', () {
    test('throws if constructed with an empty pool', () {
      final pool = InMemoryWorkingSetPool();
      expect(
        () => SlideshowEngine(
          pool: pool,
          sources: const {},
          resolveItem: (entry) async => null,
        ),
        throwsArgumentError,
      );
    });

    test('start() resolves and shows the first item immediately', () async {
      final fixture = _buildFixture();
      await _populate(fixture.source, fixture.pool, fixture.itemsByKey);

      fakeAsync((async) {
        final engine = SlideshowEngine(
          pool: fixture.pool,
          sources: {fixture.source.id: fixture.source},
          resolveItem: (entry) async => fixture.itemsByKey[entry.key],
          config: const SlideshowConfig(interval: Duration(seconds: 10)),
        );

        engine.start();
        async.flushMicrotasks();

        expect(engine.isRunning, isTrue);
        expect(engine.currentItem, isNotNull);
        expect(engine.currentSource, same(fixture.source));

        engine.dispose();
      });
    });

    test('advances to a new item after the configured interval elapses', () async {
      final fixture = _buildFixture();
      await _populate(fixture.source, fixture.pool, fixture.itemsByKey);

      fakeAsync((async) {
        final engine = SlideshowEngine(
          pool: fixture.pool,
          sources: {fixture.source.id: fixture.source},
          resolveItem: (entry) async => fixture.itemsByKey[entry.key],
          // noRepeatWindow guarantees the very next draw differs from the
          // current one as long as more than one candidate exists.
          config: const SlideshowConfig(interval: Duration(seconds: 5), noRepeatWindow: 1),
        );

        engine.start();
        async.flushMicrotasks();
        final first = engine.currentItem;
        expect(first, isNotNull);

        // Not yet at the interval boundary: still showing the same item.
        async.elapse(const Duration(seconds: 4));
        expect(engine.currentItem, same(first));

        // Crossing the interval boundary triggers exactly one advance.
        async.elapse(const Duration(seconds: 1));
        expect(engine.currentItem, isNot(same(first)));

        engine.dispose();
      });
    });

    test('emits every advance on currentItemChanges', () async {
      final fixture = _buildFixture();
      await _populate(fixture.source, fixture.pool, fixture.itemsByKey);

      fakeAsync((async) {
        final engine = SlideshowEngine(
          pool: fixture.pool,
          sources: {fixture.source.id: fixture.source},
          resolveItem: (entry) async => fixture.itemsByKey[entry.key],
          config: const SlideshowConfig(interval: Duration(seconds: 3), noRepeatWindow: 1),
        );

        final seen = <PhotoItem?>[];
        engine.currentItemChanges.listen(seen.add);

        engine.start();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));

        // Initial resolve + two timer-driven advances.
        expect(seen.length, 3);

        engine.dispose();
      });
    });

    test('does not prefetch beyond the current item (documented current scope)', () async {
      // SlideshowEngine's own doc comment states prefetching upcoming items
      // is intentionally not implemented here (left to a future
      // UI/controller layer). This test locks in that current behaviour:
      // resolveItem is invoked exactly once per advance, never ahead of
      // time for items that haven't been shown yet.
      final fixture = _buildFixture(itemsPerFolder: 20);
      await _populate(fixture.source, fixture.pool, fixture.itemsByKey);

      var resolveCalls = 0;
      fakeAsync((async) {
        final engine = SlideshowEngine(
          pool: fixture.pool,
          sources: {fixture.source.id: fixture.source},
          resolveItem: (entry) async {
            resolveCalls++;
            return fixture.itemsByKey[entry.key];
          },
          config: const SlideshowConfig(interval: Duration(seconds: 10), noRepeatWindow: 1),
        );

        engine.start();
        async.flushMicrotasks();
        expect(resolveCalls, 1);

        async.elapse(const Duration(seconds: 10));
        expect(resolveCalls, 2);

        async.elapse(const Duration(seconds: 10));
        expect(resolveCalls, 3);

        engine.dispose();
      });
    });

    test('stop() pauses advancing and start() resumes it', () async {
      final fixture = _buildFixture();
      await _populate(fixture.source, fixture.pool, fixture.itemsByKey);

      fakeAsync((async) {
        final engine = SlideshowEngine(
          pool: fixture.pool,
          sources: {fixture.source.id: fixture.source},
          resolveItem: (entry) async => fixture.itemsByKey[entry.key],
          config: const SlideshowConfig(interval: Duration(seconds: 5), noRepeatWindow: 1),
        );

        engine.start();
        async.flushMicrotasks();
        final beforePause = engine.currentItem;

        engine.stop();
        expect(engine.isRunning, isFalse);

        // Time passing while stopped must not advance the item.
        async.elapse(const Duration(seconds: 20));
        expect(engine.currentItem, same(beforePause));

        engine.start();
        async.flushMicrotasks();
        expect(engine.isRunning, isTrue);
        // Resuming immediately re-resolves the current item (per `start()`
        // always calling `_advance()` once up front).
        async.elapse(const Duration(seconds: 5));
        expect(engine.currentItem, isNotNull);

        engine.dispose();
      });
    });

    test('dispose() cancels the timer and leaves no further advances', () async {
      final fixture = _buildFixture();
      await _populate(fixture.source, fixture.pool, fixture.itemsByKey);

      fakeAsync((async) {
        final engine = SlideshowEngine(
          pool: fixture.pool,
          sources: {fixture.source.id: fixture.source},
          resolveItem: (entry) async => fixture.itemsByKey[entry.key],
          config: const SlideshowConfig(interval: Duration(seconds: 5), noRepeatWindow: 1),
        );

        engine.start();
        async.flushMicrotasks();
        final lastItem = engine.currentItem;

        engine.dispose();
        expect(engine.isRunning, isFalse);

        // No pending timers must remain after dispose (a leaked
        // Timer.periodic would show up here as a still-pending timer that
        // fakeAsync's elapse would otherwise happily fire).
        expect(async.pendingTimers, isEmpty);

        async.elapse(const Duration(minutes: 5));
        expect(engine.currentItem, same(lastItem));
      });
    });

    test('skipToNext() advances immediately without waiting for the timer', () async {
      final fixture = _buildFixture();
      await _populate(fixture.source, fixture.pool, fixture.itemsByKey);

      fakeAsync((async) {
        final engine = SlideshowEngine(
          pool: fixture.pool,
          sources: {fixture.source.id: fixture.source},
          resolveItem: (entry) async => fixture.itemsByKey[entry.key],
          config: const SlideshowConfig(interval: Duration(seconds: 30), noRepeatWindow: 1),
        );

        engine.start();
        async.flushMicrotasks();
        final first = engine.currentItem;

        engine.skipToNext();
        async.flushMicrotasks();
        expect(engine.currentItem, isNot(same(first)));

        engine.dispose();
      });
    });
  });
}
