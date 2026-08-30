import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/index/media_index_entry.dart';
import 'package:mobile_app/features/slideshow/domain/date_filter.dart';

MediaIndexEntry _entry(String name, {DateTime? takenAt}) {
  final now = DateTime(2024, 1, 1);
  return MediaIndexEntry(
    sourceId: 'src-1',
    path: name,
    name: name,
    size: 1024,
    mtime: now,
    lastSeenAt: now,
    takenAt: takenAt,
  );
}

void main() {
  group('filterByDateRange', () {
    test('includes entries within the (inclusive) range', () {
      final entries = [
        _entry('a', takenAt: DateTime(2023, 6, 1)),
        _entry('b', takenAt: DateTime(2023, 6, 15)),
        _entry('c', takenAt: DateTime(2023, 6, 30)),
        _entry('d', takenAt: DateTime(2023, 7, 1)),
      ];
      final range = DateRange(start: DateTime(2023, 6, 1), end: DateTime(2023, 6, 30));

      final result = filterByDateRange(entries, range);

      expect(result.map((e) => e.name), ['a', 'b', 'c']);
    });

    test('excludes entries with a null takenAt', () {
      final entries = [_entry('undated'), _entry('dated', takenAt: DateTime(2023, 6, 1))];
      final range = DateRange(start: DateTime(2023, 1, 1), end: DateTime(2023, 12, 31));

      final result = filterByDateRange(entries, range);

      expect(result.map((e) => e.name), ['dated']);
    });

    test('a year-boundary-spanning range includes both sides of New Year', () {
      final entries = [
        _entry('dec30', takenAt: DateTime(2023, 12, 30)),
        _entry('jan2', takenAt: DateTime(2024, 1, 2)),
        _entry('feb1', takenAt: DateTime(2024, 2, 1)),
      ];
      final range = DateRange(start: DateTime(2023, 12, 25), end: DateTime(2024, 1, 5));

      final result = filterByDateRange(entries, range);

      expect(result.map((e) => e.name), ['dec30', 'jan2']);
    });
  });

  group('filterOnThisDay', () {
    test('matches same month+day regardless of year', () {
      final entries = [
        _entry('this-year', takenAt: DateTime(2024, 6, 15)),
        _entry('last-year', takenAt: DateTime(2020, 6, 15)),
        _entry('ancient', takenAt: DateTime(1999, 6, 15)),
        _entry('different-day', takenAt: DateTime(2020, 6, 16)),
      ];

      final result = filterOnThisDay(entries, today: DateTime(2024, 6, 15));

      expect(
        result.map((e) => e.name).toSet(),
        {'this-year', 'last-year', 'ancient'},
      );
    });

    test('excludes entries with a null takenAt', () {
      final entries = [_entry('undated'), _entry('dated', takenAt: DateTime(2020, 6, 15))];

      final result = filterOnThisDay(entries, today: DateTime(2024, 6, 15));

      expect(result.map((e) => e.name), ['dated']);
    });

    test('a Feb 29 photo also surfaces on Feb 28 in a non-leap year', () {
      final entries = [_entry('leap-photo', takenAt: DateTime(2020, 2, 29))];

      // 2023 is not a leap year - there is no Feb 29 for it to match exactly.
      final result = filterOnThisDay(entries, today: DateTime(2023, 2, 28));

      expect(result.map((e) => e.name), ['leap-photo']);
    });

    test('a Feb 29 "today" (leap year) also surfaces Feb 28 photos', () {
      final entries = [_entry('feb28-photo', takenAt: DateTime(2019, 2, 28))];

      final result = filterOnThisDay(entries, today: DateTime(2024, 2, 29));

      expect(result.map((e) => e.name), ['feb28-photo']);
    });

    test('a Feb 29 "today" still matches an exact Feb 29 photo from another leap year', () {
      final entries = [_entry('feb29-photo', takenAt: DateTime(2016, 2, 29))];

      final result = filterOnThisDay(entries, today: DateTime(2024, 2, 29));

      expect(result.map((e) => e.name), ['feb29-photo']);
    });

    test('Feb 28 "today" in a non-leap year does not match unrelated dates', () {
      final entries = [
        _entry('feb27', takenAt: DateTime(2019, 2, 27)),
        _entry('mar1', takenAt: DateTime(2019, 3, 1)),
      ];

      final result = filterOnThisDay(entries, today: DateTime(2023, 2, 28));

      expect(result, isEmpty);
    });

    test('a year-boundary "today" of Jan 1 matches photos from any Jan 1', () {
      final entries = [
        _entry('jan1-2020', takenAt: DateTime(2020, 1, 1)),
        _entry('dec31-2020', takenAt: DateTime(2020, 12, 31)),
      ];

      final result = filterOnThisDay(entries, today: DateTime(2024, 1, 1));

      expect(result.map((e) => e.name), ['jan1-2020']);
    });
  });
}
