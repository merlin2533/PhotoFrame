import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/favorites_store.dart';

/// Provides a single, app-wide [FavoritesStore] instance. It is loaded
/// eagerly (fire-and-forget) as soon as the provider is first read; UI code
/// should not assume [FavoritesStore.isLoaded] is `true` on the very first
/// frame - `favoriteIds`/`isFavorite` simply report "not favorited" until
/// the load completes, which is an acceptable, harmless default (nothing
/// gets wrongly hidden/shown, at worst a favorite toggle briefly appears
/// unset for a frame or two).
///
/// A [ChangeNotifierProvider] (rather than an `AsyncNotifierProvider`) is
/// used deliberately so widgets can keep reading a synchronously-available
/// `FavoritesStore` and simply rebuild via `ref.watch` whenever it calls
/// `notifyListeners()` - there is no meaningful "loading" UI state to model
/// for a background favorites-set fetch.
final ChangeNotifierProvider<FavoritesStore> favoritesStoreProvider =
    ChangeNotifierProvider<FavoritesStore>((ref) {
  final store = FavoritesStore();
  // Fire-and-forget: `ref.onDispose`-safe because `load()` only touches the
  // store's own fields/notifyListeners, never `ref` itself.
  unawaited(store.load());
  return store;
});
