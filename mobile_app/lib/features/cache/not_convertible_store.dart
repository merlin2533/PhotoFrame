import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/app_log.dart';
import '../settings/state/settings_providers.dart';

/// Persistent set of photo stableIds whose screen-sized copy could not be
/// made (unsupported format or a failing scaler).
///
/// A photo in this set is never scaled again. The slideshow shows its original
/// download instead. The set is kept in `shared_preferences` (the same store as
/// the app settings), not in the cache folder, so that clearing the cache
/// does not forget it and the cache usage does not count it.
class NotConvertibleStore {
  NotConvertibleStore({required Future<SharedPreferences> Function() prefs})
      : _prefs = prefs;

  /// Key of the string list in `shared_preferences`.
  static const prefsKey = 'not_convertible_stable_ids_v1';

  final Future<SharedPreferences> Function() _prefs;

  /// The set after the first successful read. `null` until then.
  Set<String>? _ids;

  /// All stableIds marked as not convertible. Read from the preferences once
  /// and kept in memory afterwards. A failed read yields an empty set and is
  /// tried again on the next call.
  Future<Set<String>> load() async {
    final cached = _ids;
    if (cached != null) return cached;
    try {
      final prefs = await _prefs();
      final ids = {...?prefs.getStringList(prefsKey)};
      _ids = ids;
      return ids;
    } catch (e, st) {
      logRecoverableError(
        'Not-convertible photo list could not be read',
        error: e,
        stackTrace: st,
      );
      return {};
    }
  }

  /// `true` when [stableId] was marked as not convertible.
  Future<bool> contains(String stableId) async =>
      (await load()).contains(stableId);

  /// Marks [stableId] and writes the set to the preferences. Marking a photo
  /// twice does nothing.
  Future<void> add(String stableId) async {
    final ids = await load();
    if (!ids.add(stableId)) return;
    try {
      final prefs = await _prefs();
      await prefs.setStringList(prefsKey, ids.toList()..sort());
    } catch (e, st) {
      // The photo stays marked in memory for this session; the next start
      // may try it once more.
      logRecoverableError(
        'Not-convertible photo list could not be saved',
        error: e,
        stackTrace: st,
      );
    }
  }
}

final Provider<NotConvertibleStore> notConvertibleStoreProvider =
    Provider<NotConvertibleStore>(
  (ref) => NotConvertibleStore(
    prefs: () => ref.read(sharedPreferencesProvider),
  ),
);
