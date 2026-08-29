import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent store of favorited item ids (see `MediaStableId` for how those
/// ids are derived), consistent with how [AppSettings] persists as a single
/// JSON blob in `shared_preferences` rather than a database table - the
/// favorites set is similarly small and simple enough that a KV blob is
/// simpler than standing up a `drift` table for it.
///
/// A [ChangeNotifier] so it plugs directly into Riverpod's
/// `ChangeNotifierProvider` (see `favorites_providers.dart`) for UI updates,
/// and additionally exposes [changes] as a plain broadcast [Stream] for
/// callers that would rather not depend on `Listenable`.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore({SharedPreferences? prefs}) : _injectedPrefs = prefs;

  static const String _storageKey = 'favorites.itemIds.v1';

  final SharedPreferences? _injectedPrefs;
  SharedPreferences? _prefs;

  Set<String> _favoriteIds = <String>{};
  bool _loaded = false;

  final StreamController<Set<String>> _changesController =
      StreamController<Set<String>>.broadcast();

  /// Whether [load] has completed at least once.
  bool get isLoaded => _loaded;

  /// All currently favorited item ids (stable ids - see `MediaStableId`).
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  /// Emits the current favorite-id set every time it changes (including
  /// once right after [load] completes).
  Stream<Set<String>> get changes => _changesController.stream;

  Future<SharedPreferences> _resolvePrefs() async {
    final cached = _prefs;
    if (cached != null) return cached;
    final prefs = _injectedPrefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    return prefs;
  }

  /// Loads the persisted favorite ids. Safe to call multiple times (e.g. on
  /// every provider rebuild); subsequent calls just re-read from storage.
  Future<void> load() async {
    final prefs = await _resolvePrefs();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _favoriteIds = decoded.map((e) => e.toString()).toSet();
      } on FormatException {
        // Corrupt/old-format value - fall back to an empty set rather than
        // crash app startup over a favorites-persistence glitch.
        _favoriteIds = <String>{};
      }
    }
    _loaded = true;
    _emit();
  }

  /// Whether [itemId] is currently favorited.
  bool isFavorite(String itemId) => _favoriteIds.contains(itemId);

  /// Flips the favorite state of [itemId] and persists the result.
  Future<void> toggleFavorite(String itemId) => setFavorite(itemId, !isFavorite(itemId));

  /// Sets the favorite state of [itemId] explicitly and persists the result.
  /// No-op (and does not persist/notify) if the state is already as
  /// requested.
  Future<void> setFavorite(String itemId, bool value) async {
    final changed = value ? _favoriteIds.add(itemId) : _favoriteIds.remove(itemId);
    if (!changed) return;
    await _persist();
    _emit();
  }

  Future<void> _persist() async {
    final prefs = await _resolvePrefs();
    await prefs.setString(_storageKey, jsonEncode(_favoriteIds.toList(growable: false)));
  }

  void _emit() {
    notifyListeners();
    if (!_changesController.isClosed) {
      _changesController.add(favoriteIds);
    }
  }

  @override
  void dispose() {
    _changesController.close();
    super.dispose();
  }
}
