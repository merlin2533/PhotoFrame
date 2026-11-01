import 'dart:math';

import 'package:mobile_app/features/index/working_set_pool.dart';
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

    test('a pool smaller than the cap still fills the window by repeating',
        () {
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
}

extension on PhotoItem {
  /// The pool entry of this photo, for tests that add it by hand.
  PoolEntry toPoolEntry() => PoolEntry(
        sourceId: sourceId,
        itemId: id,
        addedToPoolAt: DateTime(2024, 1, 1),
      );
}
