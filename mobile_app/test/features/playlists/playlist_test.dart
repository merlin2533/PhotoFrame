import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/index/media_index_entry.dart';
import 'package:mobile_app/features/index/media_stable_id.dart';
import 'package:mobile_app/features/playlists/playlist.dart';
import 'package:mobile_app/features/slideshow/domain/date_filter.dart';

MediaIndexEntry _entry(String path, {DateTime? takenAt}) {
  final now = DateTime(2024, 1, 1);
  return MediaIndexEntry(
    sourceId: 'src-1',
    path: path,
    name: path,
    size: 1024,
    mtime: now,
    lastSeenAt: now,
    takenAt: takenAt,
  );
}

void main() {
  group('MediaStableId', () {
    test('is deterministic for the same sourceId+path', () {
      final a = MediaStableId.compute(sourceId: 's1', path: '/a/b.jpg');
      final b = MediaStableId.compute(sourceId: 's1', path: '/a/b.jpg');
      expect(a, b);
    });

    test('differs for different paths within the same source', () {
      final a = MediaStableId.compute(sourceId: 's1', path: '/a/b.jpg');
      final b = MediaStableId.compute(sourceId: 's1', path: '/a/c.jpg');
      expect(a, isNot(b));
    });

    test('differs for the same path across different sources', () {
      final a = MediaStableId.compute(sourceId: 's1', path: '/a/b.jpg');
      final b = MediaStableId.compute(sourceId: 's2', path: '/a/b.jpg');
      expect(a, isNot(b));
    });

    test('MediaIndexEntry.stableId is stable across separate instances of the same entry', () {
      final e1 = _entry('/a/b.jpg');
      final e2 = _entry('/a/b.jpg');
      expect(e1.stableId, e2.stableId);
    });
  });

  group('applyPlaylistFilter', () {
    Iterable<MediaIndexEntry> apply(
      List<MediaIndexEntry> entries,
      PlaylistFilter filter, {
      bool Function(String)? isFavorite,
    }) {
      return applyPlaylistFilter<MediaIndexEntry>(
        entries,
        filter,
        stableIdOf: (e) => e.stableId,
        takenAtOf: (e) => e.takenAt,
        isFavorite: isFavorite ?? (_) => false,
      );
    }

    test('a no-op filter (all defaults) returns every candidate unchanged', () {
      final entries = [_entry('a'), _entry('b')];
      final result = apply(entries, const PlaylistFilter());
      expect(result, entries);
    });

    test('favoritesOnly keeps only candidates the callback marks favorited', () {
      final a = _entry('a');
      final b = _entry('b');
      final result = apply(
        [a, b],
        const PlaylistFilter(favoritesOnly: true),
        isFavorite: (id) => id == a.stableId,
      );
      expect(result.toList(), [a]);
    });

    test('dateRange keeps only candidates whose takenAt falls inside the range', () {
      final inRange = _entry('in', takenAt: DateTime(2023, 6, 15));
      final outOfRange = _entry('out', takenAt: DateTime(2022, 1, 1));
      final undated = _entry('undated');

      final result = apply(
        [inRange, outOfRange, undated],
        PlaylistFilter(
          dateRange: DateRange(start: DateTime(2023, 1, 1), end: DateTime(2023, 12, 31)),
        ),
      );

      expect(result.toList(), [inRange]);
    });

    test('excludeIds drops candidates whose stable id is listed', () {
      final a = _entry('a');
      final b = _entry('b');

      final result = apply(
        [a, b],
        PlaylistFilter(excludeIds: {a.stableId}),
      );

      expect(result.toList(), [b]);
    });

    test('all three filter fields combine with AND semantics', () {
      final favoriteInRange = _entry('keep', takenAt: DateTime(2023, 6, 1));
      final favoriteOutOfRange = _entry('drop-date', takenAt: DateTime(2020, 1, 1));
      final nonFavoriteInRange = _entry('drop-fav', takenAt: DateTime(2023, 6, 2));

      final result = apply(
        [favoriteInRange, favoriteOutOfRange, nonFavoriteInRange],
        PlaylistFilter(
          favoritesOnly: true,
          dateRange: DateRange(start: DateTime(2023, 1, 1), end: DateTime(2023, 12, 31)),
        ),
        isFavorite: (id) =>
            id == favoriteInRange.stableId || id == favoriteOutOfRange.stableId,
      );

      expect(result.toList(), [favoriteInRange]);
    });
  });

  group('PlaylistFilter JSON round-trip', () {
    test('round-trips favoritesOnly/dateRange/excludeIds', () {
      final filter = PlaylistFilter(
        favoritesOnly: true,
        dateRange: DateRange(start: DateTime(2023, 1, 1), end: DateTime(2023, 12, 31)),
        excludeIds: {'id-1', 'id-2'},
      );

      final restored = PlaylistFilter.fromJson(filter.toJson());

      expect(restored.favoritesOnly, isTrue);
      expect(restored.dateRange!.start, DateTime(2023, 1, 1));
      expect(restored.dateRange!.end, DateTime(2023, 12, 31));
      expect(restored.excludeIds, {'id-1', 'id-2'});
    });

    test('a default PlaylistFilter round-trips as a no-op', () {
      const filter = PlaylistFilter();
      final restored = PlaylistFilter.fromJson(filter.toJson());
      expect(restored.isNoOp, isTrue);
    });
  });
}
