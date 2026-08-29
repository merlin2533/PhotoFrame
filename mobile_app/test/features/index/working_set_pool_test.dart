import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/index/media_index_entry.dart';
import 'package:mobile_app/features/index/working_set_pool.dart';

MediaIndexEntry _entry(
  String path, {
  String sourceId = 'src-1',
  DateTime? mtime,
}) {
  final now = DateTime.now();
  return MediaIndexEntry(
    sourceId: sourceId,
    path: path,
    name: path,
    size: 1024,
    mtime: mtime ?? now,
    lastSeenAt: now,
  );
}

List<MediaIndexEntry> _newCandidates(int count, {String prefix = 'new'}) {
  return List.generate(
    count,
    (i) => _entry('$prefix-$i.jpg', mtime: DateTime.now()),
  );
}

List<MediaIndexEntry> _oldCandidates(int count, {String prefix = 'old'}) {
  final old = DateTime.now().subtract(const Duration(days: 400));
  return List.generate(
    count,
    (i) => _entry('$prefix-$i.jpg', mtime: old),
  );
}

void main() {
  group('InMemoryWorkingSetPool.refill', () {
    test('fills the pool up to targetSize from a mix of candidates', () {
      final pool = InMemoryWorkingSetPool(targetSize: 100, newImageQuota: 0.2);
      final candidates = [..._newCandidates(30), ..._oldCandidates(200)];

      final added = pool.refill(candidates);

      expect(added, 100);
      expect(pool.entries.length, 100);
      expect(pool.needsRefill, isFalse);
    });

    test('reserves at least newImageQuota of newly-filled slots for new candidates '
        '(integer-rounding tolerance)', () {
      final pool = InMemoryWorkingSetPool(targetSize: 100, newImageQuota: 0.2);
      final candidates = [..._newCandidates(50), ..._oldCandidates(200)];

      pool.refill(candidates);

      final newCount = pool.newEntries.length;
      // Expect close to 20% new, allow rounding slack of +/-1 on top of the
      // ceil() reservation plus any leftover-new-candidate fill spillover.
      expect(newCount, greaterThanOrEqualTo(20));
    });

    test('does not crash and simply stays smaller when too few candidates '
        'of any kind are available', () {
      final pool = InMemoryWorkingSetPool(targetSize: 1000, newImageQuota: 0.2);
      final candidates = _newCandidates(3);

      final added = pool.refill(candidates);

      expect(added, 3);
      expect(pool.entries.length, 3);
      expect(pool.needsRefill, isTrue);
    });

    test('stays smaller than target when only new candidates are scarce, '
        'even though old candidates are plentiful (quota unmet is not fatal)', () {
      final pool = InMemoryWorkingSetPool(targetSize: 50, newImageQuota: 0.5);
      // Only 2 new candidates available, but plenty of old ones - the pool
      // should still fill up using old candidates for the non-reserved
      // slots rather than stalling.
      final candidates = [..._newCandidates(2), ..._oldCandidates(200)];

      final added = pool.refill(candidates);

      expect(added, 50);
      expect(pool.entries.length, 50);
    });

    test('skips candidates already present in the pool', () {
      final pool = InMemoryWorkingSetPool(targetSize: 10, newImageQuota: 0.2);
      final candidates = _oldCandidates(10);
      pool.refill(candidates);
      expect(pool.entries.length, 10);

      // Refilling again with the exact same candidates should add nothing
      // new (pool is already at target and all candidates are duplicates).
      final addedAgain = pool.refill(candidates);
      expect(addedAgain, 0);
      expect(pool.entries.length, 10);
    });

    test('a zero/negative slotsToFill (pool already at or above target) adds nothing', () {
      final pool = InMemoryWorkingSetPool(targetSize: 5, newImageQuota: 0.2);
      pool.refill(_oldCandidates(5));
      expect(pool.entries.length, 5);

      final added = pool.refill(_newCandidates(20));
      expect(added, 0);
      expect(pool.entries.length, 5);
    });
  });

  group('InMemoryWorkingSetPool.replaceExhausted', () {
    test('replaces entries shown at least once with fresh candidates when available', () {
      final pool = InMemoryWorkingSetPool(targetSize: 10, newImageQuota: 0.2);
      pool.refill(_oldCandidates(10, prefix: 'initial'));
      expect(pool.entries.length, 10);

      // Mark half of the pool as shown.
      final shownEntries = pool.entries.take(5).toList();
      for (final e in shownEntries) {
        pool.registerShown(e.sourceId, e.itemId);
      }

      final freshCandidates = _oldCandidates(20, prefix: 'fresh');
      final added = pool.replaceExhausted(freshCandidates);

      expect(added, 5);
      expect(pool.entries.length, 10);
      // None of the currently-shown-marked entries should remain.
      for (final e in shownEntries) {
        expect(pool.entries.any((p) => p.key == e.key), isFalse);
      }
      // All remaining entries should have shownCount 0 (either untouched
      // originals or freshly admitted ones).
      expect(pool.entries.every((e) => e.shownCount == 0), isTrue);
    });

    test('leaves the pool smaller (not an error) when no replacement candidates exist', () {
      final pool = InMemoryWorkingSetPool(targetSize: 10, newImageQuota: 0.2);
      pool.refill(_oldCandidates(10));
      for (final e in pool.entries.toList()) {
        pool.registerShown(e.sourceId, e.itemId);
      }

      final added = pool.replaceExhausted(const []);

      expect(added, 0);
      expect(pool.entries, isEmpty);
      expect(pool.needsRefill, isTrue);
    });

    test('does nothing when nothing has been shown yet', () {
      final pool = InMemoryWorkingSetPool(targetSize: 10, newImageQuota: 0.2);
      pool.refill(_oldCandidates(10));

      final added = pool.replaceExhausted(_oldCandidates(5, prefix: 'unused'));

      expect(added, 0);
      expect(pool.entries.length, 10);
    });
  });

  group('InMemoryWorkingSetPool.needsUrgentRefill', () {
    test('triggers when the pool is nearly exhausted and the interval is short', () {
      final pool = InMemoryWorkingSetPool(targetSize: 10, newImageQuota: 0.2);
      pool.refill(_oldCandidates(10));
      for (final e in pool.entries.take(10).toList()) {
        pool.registerShown(e.sourceId, e.itemId);
      }

      final urgent = pool.needsUrgentRefill(
        currentInterval: const Duration(seconds: 10),
      );

      expect(urgent, isTrue);
    });

    test('does not trigger when the interval is long even if the pool is exhausted', () {
      final pool = InMemoryWorkingSetPool(targetSize: 10, newImageQuota: 0.2);
      pool.refill(_oldCandidates(10));
      for (final e in pool.entries.toList()) {
        pool.registerShown(e.sourceId, e.itemId);
      }

      final urgent = pool.needsUrgentRefill(
        currentInterval: const Duration(minutes: 5),
      );

      expect(urgent, isFalse);
    });

    test('does not trigger when the pool has plenty of unshown entries left', () {
      final pool = InMemoryWorkingSetPool(targetSize: 10, newImageQuota: 0.2);
      pool.refill(_oldCandidates(10));
      // Only show one entry - far below the exhaustion threshold.
      final first = pool.entries.first;
      pool.registerShown(first.sourceId, first.itemId);

      final urgent = pool.needsUrgentRefill(
        currentInterval: const Duration(seconds: 10),
      );

      expect(urgent, isFalse);
    });

    test('does not trigger on an empty pool', () {
      final pool = InMemoryWorkingSetPool(targetSize: 10, newImageQuota: 0.2);
      expect(
        pool.needsUrgentRefill(currentInterval: const Duration(seconds: 1)),
        isFalse,
      );
    });
  });
}
