import 'dart:math';

import 'package:mobile_app/features/index/working_set_pool.dart';
import 'package:mobile_app/features/slideshow/domain/rotation_swap.dart';
import 'package:mobile_app/features/slideshow/domain/shuffle_bag.dart';
import 'package:mobile_app/features/slideshow/domain/slideshow_config.dart';
import 'package:mobile_app/features/slideshow/domain/slideshow_engine.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:test/test.dart';

/// A local-looking photo with a stable id derived from [i].
PhotoItem _photo(int i) => PhotoItem(
      id: 'folder/photo$i.jpg',
      sourceId: 'src-1',
      folderId: 'folder',
      name: 'photo$i.jpg',
      mediaType: MediaType.image,
      size: 1000 + i,
      mtime: DateTime(2024, 1, 1),
    );

/// A pool plus the lookup the engine's resolver uses. Photos are admitted with
/// [admit], also after an engine was built on the pool.
class _Fixture {
  _Fixture({int count = 0}) {
    for (var i = 0; i < count; i++) {
      admit(_photo(i));
    }
  }

  final InMemoryWorkingSetPool pool = InMemoryWorkingSetPool();
  final Map<String, PhotoItem> itemsByKey = {};

  PoolEntry admit(PhotoItem item) {
    itemsByKey['${item.sourceId}::${item.id}'] = item;
    final entry = PoolEntry(
      sourceId: item.sourceId,
      itemId: item.id,
      addedToPoolAt: DateTime(2024, 1, 1),
    );
    pool.add(entry);
    return entry;
  }

  SlideshowEngine engine() => SlideshowEngine(
        pool: pool,
        sources: const {},
        resolveItem: (entry) async => itemsByKey[entry.key],
        // A long interval: the tests advance the slideshow by hand.
        config: const SlideshowConfig(
          interval: Duration(seconds: 30),
          noRepeatWindow: 1,
        ),
      );
}

/// Ids of the photos shown by [engine]: the current one, then one per
/// `skipToNext` for [advances] times.
Future<List<String>> _shownIds(SlideshowEngine engine, int advances) async {
  final shown = <String>[engine.currentItem!.id];
  for (var i = 0; i < advances; i++) {
    await engine.skipToNext();
    shown.add(engine.currentItem!.id);
  }
  return shown;
}

void main() {
  group('Rotation pool growth', () {
    test('a photo added after the engine started appears in the rotation',
        () async {
      final fixture = _Fixture(count: 2);
      final engine = fixture.engine();
      await engine.start();

      // The photo is cached only now, while the slideshow runs.
      fixture.admit(_photo(2));
      engine.refreshPool(fixture.pool);

      // The new photo comes up within the current rotation cycle: at most two
      // advances away, as only one old photo is still queued.
      final shown = await _shownIds(engine, 3);
      expect(shown, contains('folder/photo2.jpg'));

      await engine.dispose();
    });

    test('photos added in several steps all join the rotation', () async {
      final fixture = _Fixture(count: 1);
      final engine = fixture.engine();
      await engine.start();

      for (var i = 1; i <= 4; i++) {
        fixture.admit(_photo(i));
        engine.refreshPool(fixture.pool);
        // A pool of n photos is at most n draws away from any photo, so
        // n advances always reach the new one.
        final shown = await _shownIds(engine, fixture.pool.entries.length);
        expect(shown, contains('folder/photo$i.jpg'), reason: 'step $i');
      }

      await engine.dispose();
    });

    test('a photo already in the pool is not added twice', () async {
      final fixture = _Fixture(count: 2);
      final engine = fixture.engine();
      await engine.start();

      expect(fixture.pool.add(_photo(1).toPoolEntry()), isFalse);
      engine.refreshPool(fixture.pool);

      // Four shows of two photos: two full cycles, photo1 once in each.
      final shown = await _shownIds(engine, 3);
      expect(shown.where((id) => id == 'folder/photo1.jpg'), hasLength(2));

      await engine.dispose();
    });
  });

  group('Rotation repeat', () {
    test('after the last photo the rotation starts again with every photo',
        () async {
      final fixture = _Fixture(count: 3);
      final engine = fixture.engine();
      await engine.start();

      final shown = await _shownIds(engine, 8);
      final all = {for (var i = 0; i < 3; i++) 'folder/photo$i.jpg'};

      // Nine shows of three photos: three full cycles, each with every photo
      // exactly once.
      expect(shown.sublist(0, 3).toSet(), all);
      expect(shown.sublist(3, 6).toSet(), all);
      expect(shown.sublist(6, 9).toSet(), all);

      await engine.dispose();
    });

    test('the rotation keeps going on a single photo', () async {
      final fixture = _Fixture(count: 1);
      final engine = fixture.engine();
      await engine.start();

      final shown = await _shownIds(engine, 4);
      expect(shown, everyElement('folder/photo0.jpg'));

      await engine.dispose();
    });
  });

  group('Prefetch window cap', () {
    test('maxAheadCount is 100', () {
      expect(maxAheadCount, 100);
    });

    test('upcomingEntries never returns more than maxAheadCount entries', () {
      final fixture = _Fixture(count: 150);
      final engine = fixture.engine();

      expect(engine.upcomingEntries(maxAheadCount), hasLength(100));
      expect(engine.upcomingEntries(1000), hasLength(100));
      expect(engine.upcomingEntries(1 << 40), hasLength(100));
    });

    test('a pool smaller than the cap still fills the window by repeating', () {
      final fixture = _Fixture(count: 3);
      final engine = fixture.engine();

      final upcoming = engine.upcomingEntries(maxAheadCount);
      expect(upcoming, hasLength(maxAheadCount));
      // Every photo is in the window, as the rotation repeats.
      expect(upcoming.map((e) => e.key).toSet(), hasLength(3));
    });

    test('the window is a prefix of the same order for a smaller count', () {
      final fixture = _Fixture(count: 150);
      final engine = fixture.engine();

      final full = engine.upcomingEntries(maxAheadCount).map((e) => e.key);
      final head = engine.upcomingEntries(10).map((e) => e.key);
      expect(head, full.take(10));
    });
  });

  group('ShuffleBag with a growing working list', () {
    test('an item added mid-cycle is drawn in that same cycle', () {
      final bag = ShuffleBag<String>(
        ['a', 'b', 'c'],
        noRepeatWindow: 1,
        random: Random(7),
      );
      final first = bag.next();

      bag.updateItems(['a', 'b', 'c', 'd']);
      final rest = [bag.next(), bag.next(), bag.next()];

      expect({first, ...rest}, {'a', 'b', 'c', 'd'});
      expect({first, ...rest}, hasLength(4), reason: 'each item once');
    });

    test('an item added mid-cycle is shown after the rest of that cycle', () {
      final bag = ShuffleBag<String>(
        ['a', 'b', 'c'],
        noRepeatWindow: 0,
        random: Random(11),
      );
      final first = bag.next();

      bag.updateItems(['a', 'b', 'c', 'd']);
      final rest = [bag.next(), bag.next(), bag.next()];

      // The new photo is the last of the current cycle, after the photos that
      // were already in the rotation.
      expect({first, ...rest.take(2)}, {'a', 'b', 'c'});
      expect(rest.last, 'd');

      // The next cycle starts with all four photos again.
      final nextCycle = [bag.next(), bag.next(), bag.next(), bag.next()];
      expect(nextCycle.toSet(), {'a', 'b', 'c', 'd'});
    });

    test('an item drawn in the current cycle is not queued again', () {
      final bag = ShuffleBag<String>(
        ['a', 'b', 'c'],
        noRepeatWindow: 0,
        random: Random(3),
      );
      final drawn = {bag.next(), bag.next()};
      expect(drawn, hasLength(2));
      expect(bag.remainingInCycle, 1);

      // Re-passing the same list must not put the drawn photos back into the
      // current cycle: only the one still queued remains.
      bag.updateItems(['a', 'b', 'c']);
      expect(bag.remainingInCycle, 1);
      final last = bag.next();
      expect(drawn, isNot(contains(last)));
    });
  });

  group('Daily swap', () {
    test('a 100-photo pool swaps 20 photos, the default share', () {
      expect(rotationSwapSize(100), 20);
      expect(rotationSwapSize(100, percent: 5), 5);
      expect(rotationSwapSize(100, percent: 50), 50);
      expect(rotationSwapSize(1), 0);
      // Never the whole pool, and at least one photo for a small pool.
      expect(rotationSwapSize(2, percent: 50), 1);
    });

    test('the oldest photos by their entry day are chosen first', () {
      // Photo 0 entered newest, photo 4 oldest.
      final entries = [
        for (var i = 0; i < 5; i++) _entryOn(i, DateTime(2026, 10, 10 + 4 - i)),
      ];
      final oldest = oldestEntries(entries, 2);
      expect(oldest.map((e) => e.itemId),
          ['folder/photo4.jpg', 'folder/photo3.jpg']);
    });

    test('photos of the same entry day keep their pool order', () {
      final entries = [
        for (var i = 0; i < 4; i++) _entryOn(i, DateTime(2026, 10, 10)),
      ];
      final oldest = oldestEntries(entries, 2);
      expect(oldest.map((e) => e.itemId),
          ['folder/photo0.jpg', 'folder/photo1.jpg']);
    });

    test('a 100-photo pool loses its 20 oldest photos', () {
      final pool = InMemoryWorkingSetPool();
      for (var i = 0; i < 100; i++) {
        // Ten photos per day: photos 0-19 are the 20 oldest.
        pool.add(
            _entryOn(i, DateTime(2026, 10, 1).add(Duration(days: i ~/ 10))));
      }

      final removed = swapOutOldest(pool, rotationSwapSize(100));

      expect(removed, hasLength(20));
      expect(removed.map((e) => e.itemId).toSet(), {
        for (var i = 0; i < 20; i++) 'folder/photo$i.jpg',
      });
      expect(pool.entries, hasLength(80));
    });

    test('a swap never empties the pool', () {
      final pool = InMemoryWorkingSetPool();
      for (var i = 0; i < 3; i++) {
        pool.add(_entryOn(i, DateTime(2026, 10, 1)));
      }
      final removed = swapOutOldest(pool, 3);
      expect(removed, hasLength(2));
      expect(pool.entries, hasLength(1));
    });

    test('the swap runs at most once per calendar day', () {
      expect(swapDue(lastSwapDay: null, today: '2026-11-01'), isTrue);
      expect(swapDue(lastSwapDay: '2026-11-01', today: '2026-11-01'), isFalse);
      expect(swapDue(lastSwapDay: '2026-10-31', today: '2026-11-01'), isTrue);
    });

    test('replacements are the first candidates that are not skipped', () {
      final picked = nextReplacements<String>(
        candidates: const ['a', 'b', 'c', 'd'],
        skip: (c) => c == 'b',
        count: 2,
      );
      expect(picked, ['a', 'c']);
    });

    test('a photo removed by the swap leaves the rotation', () async {
      final fixture = _Fixture();
      for (var i = 0; i < 100; i++) {
        final item = _photo(i);
        fixture.itemsByKey['${item.sourceId}::${item.id}'] = item;
        fixture.pool.add(
            _entryOn(i, DateTime(2026, 10, 1).add(Duration(days: i ~/ 10))));
      }
      final engine = fixture.engine();
      await engine.start();

      final victims = {
        for (final e in swapOutOldest(fixture.pool, rotationSwapSize(100)))
          e.itemId,
      };
      engine.refreshPool(fixture.pool);

      // The first photo was shown before the swap; every later one is after it.
      final shown = await _shownIds(engine, 300);
      expect(shown.skip(1).toSet().intersection(victims), isEmpty);
      expect(fixture.pool.entries, hasLength(80));

      await engine.dispose();
    });
  });

  group('Pool growth limit', () {
    test('growth stops when the cache limit is reached', () {
      const limit = 500;
      const photoBytes = 100;
      final pool = InMemoryWorkingSetPool();
      var cached = 0;
      var i = 0;
      // Each prepared photo is admitted while the cache is below its limit.
      while (downloadsAllowed(cachedBytes: cached, limitBytes: limit)) {
        expect(pool.add(_entryOn(i, DateTime(2026, 11, 1))), isTrue);
        cached += photoBytes;
        i++;
      }
      expect(cached, limit);
      expect(pool.entries, hasLength(5));
      expect(downloadsAllowed(cachedBytes: cached, limitBytes: limit), isFalse);
    });

    test('a photo already in the pool is not added again', () {
      final pool = InMemoryWorkingSetPool();
      expect(pool.add(_entryOn(1, DateTime(2026, 11, 1))), isTrue);
      expect(pool.add(_entryOn(1, DateTime(2026, 11, 1))), isFalse);
      expect(pool.entries, hasLength(1));
    });
  });
}

/// A pool entry for photo [i] (see [_photo]) that entered the pool on [day].
PoolEntry _entryOn(int i, DateTime day) => PoolEntry(
      sourceId: 'src-1',
      itemId: 'folder/photo$i.jpg',
      addedToPoolAt: day,
    );

extension on PhotoItem {
  /// The pool entry of this photo, for tests that add it by hand.
  PoolEntry toPoolEntry() => PoolEntry(
        sourceId: sourceId,
        itemId: id,
        addedToPoolAt: DateTime(2024, 1, 1),
      );
}
