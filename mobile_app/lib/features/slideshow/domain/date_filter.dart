import '../../index/media_index_entry.dart';

/// An inclusive range of calendar dates/instants, used by the playlist
/// `dateRange` filter (see `docs/PLAN.md` playlist model:
/// `filter: {favoritesOnly, dateRange, excludeIds}`).
class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// Whether [instant] falls within `[start, end]`, both ends inclusive.
  bool contains(DateTime instant) =>
      !instant.isBefore(start) && !instant.isAfter(end);

  @override
  String toString() => 'DateRange($start - $end)';
}

/// Returns the subset of [entries] whose [MediaIndexEntry.takenAt] falls
/// within [range]. Entries with a `null` `takenAt` (EXIF date unavailable)
/// are excluded rather than included-by-default, since a date range filter
/// with no date to check against would otherwise silently show up
/// undated photos regardless of the configured range.
List<MediaIndexEntry> filterByDateRange(
  List<MediaIndexEntry> entries,
  DateRange range,
) {
  return entries
      .where((e) => e.takenAt != null && range.contains(e.takenAt!))
      .toList(growable: false);
}

/// Returns the subset of [entries] whose [MediaIndexEntry.takenAt] shares
/// today's month+day, regardless of year - i.e. "Heute vor N Jahren" /
/// "on this day in the past". [today] defaults to `DateTime.now()` and is
/// otherwise injectable for deterministic tests.
///
/// Entries with a `null` `takenAt` are excluded (same reasoning as
/// [filterByDateRange]).
///
/// **Leap-day handling (documented design decision):** Feb 29 only exists
/// once every four years, so naive month+day matching would mean a photo
/// taken on Feb 29 is only ever eligible on a future Feb 29 - a ~1-in-4
/// chance in any given year, rather than "once a year" like every other
/// date. To avoid that, this treats Feb 29 and Feb 28 as mutually matching
/// whenever one side of the comparison has no Feb 29 to land on:
///  - a photo taken on Feb 29 also matches "today" = Feb 28 in a non-leap
///    year (there is no Feb 29 that year for it to match instead), and
///  - "today" = Feb 29 (a leap year) also matches photos taken on Feb 28
///    (there was no Feb 29 in whatever year they were actually taken,
///    unless that year was itself a leap year, which the exact month+day
///    match above already covers).
List<MediaIndexEntry> filterOnThisDay(
  List<MediaIndexEntry> entries, {
  DateTime? today,
}) {
  final reference = today ?? DateTime.now();
  return entries
      .where((e) => e.takenAt != null && _isSameMonthDay(e.takenAt!, reference))
      .toList(growable: false);
}

bool _isSameMonthDay(DateTime taken, DateTime reference) {
  if (taken.month == reference.month && taken.day == reference.day) {
    return true;
  }
  // Feb 29 photo, non-leap-year "today" landing on Feb 28 - see doc comment.
  if (taken.month == 2 &&
      taken.day == 29 &&
      reference.month == 2 &&
      reference.day == 28 &&
      !_isLeapYear(reference.year)) {
    return true;
  }
  // Leap-year "today" = Feb 29, photo taken on Feb 28 - see doc comment.
  if (reference.month == 2 &&
      reference.day == 29 &&
      taken.month == 2 &&
      taken.day == 28) {
    return true;
  }
  return false;
}

bool _isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
