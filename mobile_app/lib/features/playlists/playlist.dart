import '../slideshow/domain/date_filter.dart';
import '../sources/domain/photo_folder.dart';

/// A time-of-day window a [Playlist] is scheduled to be active in, e.g.
/// "only show the vacation playlist 18:00-22:00". Deliberately minimal - the
/// v1 UI has no playlist scheduling screen yet (see `docs/PLAN.md`
/// "Playlist-Modell (Schema jetzt, UI später)"); this only fixes the shape
/// so a later milestone can add a UI without a data-model rewrite.
class TimeOfDayRange {
  const TimeOfDayRange({required this.startMinutes, required this.endMinutes});

  /// Minutes since midnight, e.g. `18 * 60` for 18:00.
  final int startMinutes;
  final int endMinutes;

  Map<String, dynamic> toJson() => {
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
      };

  factory TimeOfDayRange.fromJson(Map<String, dynamic> json) => TimeOfDayRange(
        startMinutes: json['startMinutes'] as int? ?? 0,
        endMinutes: json['endMinutes'] as int? ?? 0,
      );
}

/// Filter options narrowing which items of a [Playlist]'s configured
/// sources/folders are actually eligible to be shown - per
/// `docs/PLAN.md`: `filter: {favoritesOnly, dateRange, excludeIds}`.
///
/// All fields are additive/optional: the default (`favoritesOnly: false`,
/// `dateRange: null`, `excludeIds: {}`) filters out nothing, preserving
/// today's existing "show everything configured" behaviour. Use
/// [applyPlaylistFilter] to actually run a filter against a candidate list.
class PlaylistFilter {
  const PlaylistFilter({
    this.favoritesOnly = false,
    this.dateRange,
    this.excludeIds = const <String>{},
  });

  /// When `true`, only items whose stable id (see `MediaStableId`) is
  /// currently favorited (see `FavoritesStore`) are eligible.
  final bool favoritesOnly;

  /// When set, only items taken within this date range are eligible (see
  /// `filterByDateRange`). `null` means no date restriction.
  final DateRange? dateRange;

  /// Stable ids (see `MediaStableId`) to always exclude, regardless of the
  /// other filter fields - e.g. a future "nie wieder zeigen" feature.
  final Set<String> excludeIds;

  bool get isNoOp =>
      !favoritesOnly && dateRange == null && excludeIds.isEmpty;

  PlaylistFilter copyWith({
    bool? favoritesOnly,
    DateRange? dateRange,
    bool clearDateRange = false,
    Set<String>? excludeIds,
  }) {
    return PlaylistFilter(
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      excludeIds: excludeIds ?? this.excludeIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'favoritesOnly': favoritesOnly,
        if (dateRange != null)
          'dateRange': {
            'start': dateRange!.start.toIso8601String(),
            'end': dateRange!.end.toIso8601String(),
          },
        'excludeIds': excludeIds.toList(growable: false),
      };

  factory PlaylistFilter.fromJson(Map<String, dynamic> json) {
    final rangeJson = json['dateRange'];
    return PlaylistFilter(
      favoritesOnly: json['favoritesOnly'] as bool? ?? false,
      dateRange: rangeJson is Map
          ? DateRange(
              start: DateTime.parse(rangeJson['start'] as String),
              end: DateTime.parse(rangeJson['end'] as String),
            )
          : null,
      excludeIds: (json['excludeIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toSet(),
    );
  }
}

/// A named selection of sources/folders plus an optional [PlaylistFilter]
/// and [schedule] - per `docs/PLAN.md` "Playlist-Modell (Schema jetzt, UI
/// später)": the data model is defined now so multiple playlists/schedules
/// can be added later without a rewrite, even though v1's UI only ever
/// drives a single implicit "currently configured sources" playlist.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.sourceIds = const <String>[],
    this.folders = const <PhotoFolder>[],
    this.filter = const PlaylistFilter(),
    this.schedule,
  });

  final String id;
  final String name;

  /// Ids of the [PhotoSource]s this playlist draws from.
  final List<String> sourceIds;

  /// Specific folders to restrict to, or empty for "all folders of the
  /// configured sources".
  final List<PhotoFolder> folders;

  final PlaylistFilter filter;

  /// When this playlist is allowed to be active, or `null` for "always".
  final TimeOfDayRange? schedule;

  Playlist copyWith({
    String? name,
    List<String>? sourceIds,
    List<PhotoFolder>? folders,
    PlaylistFilter? filter,
    TimeOfDayRange? schedule,
    bool clearSchedule = false,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      sourceIds: sourceIds ?? this.sourceIds,
      folders: folders ?? this.folders,
      filter: filter ?? this.filter,
      schedule: clearSchedule ? null : (schedule ?? this.schedule),
    );
  }
}

/// Applies [filter] to [candidates], returning only the items that pass
/// every configured filter field (favoritesOnly AND dateRange AND not in
/// excludeIds).
///
/// Generic over the candidate type `T` so the same filter logic works
/// against both `MediaIndexEntry` (the persisted-index shape describes in
/// `docs/PLAN.md`, used by `WorkingSetPool.refill`) and `PhotoItem` (the
/// in-memory shape the current slideshow scaffold builds directly, see
/// `slideshow_screen.dart`) without duplicating the filter logic per type -
/// callers supply small accessor callbacks instead.
///
/// This is purely additive: passing the default `PlaylistFilter()`
/// ([PlaylistFilter.isNoOp] is `true`) returns [candidates] unchanged, so
/// wiring this in never changes existing behaviour unless a caller actually
/// configures a non-default filter.
Iterable<T> applyPlaylistFilter<T>(
  Iterable<T> candidates,
  PlaylistFilter filter, {
  required String Function(T candidate) stableIdOf,
  required DateTime? Function(T candidate) takenAtOf,
  required bool Function(String stableId) isFavorite,
}) {
  if (filter.isNoOp) return candidates;

  Iterable<T> result = candidates;
  if (filter.favoritesOnly) {
    result = result.where((c) => isFavorite(stableIdOf(c)));
  }
  final range = filter.dateRange;
  if (range != null) {
    result = result.where((c) {
      final takenAt = takenAtOf(c);
      return takenAt != null && range.contains(takenAt);
    });
  }
  if (filter.excludeIds.isNotEmpty) {
    result = result.where((c) => !filter.excludeIds.contains(stableIdOf(c)));
  }
  return result;
}
