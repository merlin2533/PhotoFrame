import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/app_log.dart';
import '../../../services/ambient/ambient_dim_controller.dart';
import '../../../services/ambient/ambient_light_source.dart';
import '../../../services/kiosk/kiosk_mode_controller.dart';
import '../../cache/small_photo_cache.dart';
import '../../favorites/domain/favorites_store.dart';
import '../../favorites/state/favorites_providers.dart';
import '../../index/photo_index_store.dart';
import '../../index/working_set_pool.dart';
import '../../playlists/playlist.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_providers.dart';
import '../../sources/domain/photo_folder.dart';
import '../../sources/domain/photo_item.dart';
import '../../sources/domain/photo_source.dart';
import '../../sources/state/source_stats.dart';
import '../../sources/state/sources_providers.dart';
import '../domain/always_on_controller.dart';
import '../domain/daily_selection.dart';
import '../domain/effective_visual_settings.dart';
import '../domain/night_schedule.dart';
import '../domain/slideshow_config.dart';
import '../domain/slideshow_engine.dart';
import '../domain/transition_picker.dart';
import '../state/slideshow_providers.dart';
import 'widgets/caption_overlay.dart';
import 'widgets/clock_overlay.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/ken_burns_effect.dart';
import 'widgets/path_overlay.dart';
import 'widgets/preparing_view.dart';
import 'widgets/slide_renderer.dart';
import 'widgets/source_label_overlay.dart';
import 'widgets/touch_control_overlay.dart';
import 'widgets/weather_overlay.dart';

/// Ambient light source for [AmbientDimController]. Defaults to the no-op
/// source (no light sensor plugin yet), so ambient dimming uses its time
/// window alone. Override this provider once a real sensor source exists.
final Provider<AmbientLightSource> ambientLightSourceProvider =
    Provider<AmbientLightSource>((ref) => const NoopAmbientLightSource());

/// Opacity used for the time-window dim when no light sensor is available.
const double _fixedAmbientDimOpacity = 0.6;

/// Empties the network photo cache. Overridden in widget tests, where real
/// file-system calls never complete under the fake clock.
final Provider<Future<void> Function()> networkCacheCleanerProvider =
    Provider<Future<void> Function()>(
  (ref) => () => clearNetworkCache(
        isWorkerRunning: () => ref.read(smallPhotoWorkerProvider).running,
      ),
);

/// Downloaded photos of network sources live in the temp directory (see
/// `fetchToCache` of the Nextcloud and SMB sources). Cleared on every
/// (re)load so the cache never grows across sessions.
///
/// A file modified within [keepRecent] may still be downloaded or scaled, so it
/// is kept. Nothing is removed while the small-photo worker is running
/// ([isWorkerRunning]). That flag only turns true after the first photo of a
/// run is done, so a run that has just started is covered by [keepRecent] alone.
Future<void> clearNetworkCache({
  Directory? directory,
  bool Function()? isWorkerRunning,
  Duration keepRecent = const Duration(minutes: 10),
}) async {
  try {
    if (isWorkerRunning?.call() ?? false) {
      debugPrint('Cache cleanup skipped: small photo worker is running');
      return;
    }
    final dir = directory ?? Directory.systemTemp;
    if (!await dir.exists()) return;
    final now = DateTime.now();
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is File &&
          (name.startsWith('nextcloud_') ||
              name.startsWith('smb_') ||
              name.startsWith('immich_'))) {
        try {
          final modified = (await entity.stat()).modified;
          if (now.difference(modified) < keepRecent) continue;
          await entity.delete();
        } catch (e) {
          debugPrint('Cache cleanup skipped $name: $e');
        }
      }
    }
  } catch (e) {
    debugPrint('Cache cleanup failed: $e');
  }
}

/// Hosts the existing [SlideshowEngine], rendering [SlideshowEngine.currentItem]
/// with the configured [DisplayMode]/transition and the clock/source-label
/// overlays, plus touch controls and the empty state.
///
/// This screen owns crawling every registered [PhotoSource] once (via
/// `listFolders`/`listImages`) to build an initial [WorkingSetPool] - a
/// simplified stand-in for the real, persisted `media_index.dart` +
/// `pool_maintenance_job.dart` pipeline described in `docs/PLAN.md`, which
/// is out of scope for this milestone. `SlideshowEngine` itself is reused
/// unchanged.
class SlideshowScreen extends ConsumerStatefulWidget {
  const SlideshowScreen({
    super.key,
    this.preparedWaitLimit = defaultPreparedWaitLimit,
  });

  /// How long the start waits for the first prepared small copies before the
  /// engine starts anyway (see `_preferPrepared`). Only tests pass another value.
  final Duration preparedWaitLimit;

  static const defaultPreparedWaitLimit = Duration(minutes: 3);

  @override
  ConsumerState<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends ConsumerState<SlideshowScreen> {
  SlideshowEngine? _engine;
  bool _paused = false;
  bool _loading = true;
  Object? _loadError;
  // True only while the start path waits in `_preferPrepared` for the first
  // prepared copies and no engine exists yet. `build` shows `PreparingView`
  // then. Set and cleared by `_awaitPreparedAtStart`, which clears it on every
  // exit (success, error, early return), and also in `dispose`.
  bool _awaitingPrepared = false;
  // Minute timer for the night/dim overlays. Only runs while a night schedule
  // or the ambient dim window is configured (see `_syncMinuteTimer`). It bumps
  // `_minuteTick` instead of calling `setState`, so only the dim layers rebuild.
  Timer? _nightTick;
  final ValueNotifier<int> _minuteTick = ValueNotifier<int>(0);
  Timer? _refreshTimer;
  StreamSubscription<PhotoItem?>? _prefetchSub;
  final math.Random _prefetchRandom = math.Random();
  InMemoryWorkingSetPool? _pool;
  final Map<String, PhotoItem> _itemsByKey = {};
  bool _refreshing = false;

  // Ambient dimming: the light source is subscribed for the screen's whole
  // lifetime (a no-op stream by default); its readings drive `_sensorDimOpacity`.
  late final AmbientLightSource _ambientSource;
  StreamSubscription<double>? _ambientSub;
  final AmbientDimController _ambientDim = AmbientDimController();
  double _sensorDimOpacity = 0;

  static const _dailyKey = 'daily_selection_v1';

  /// Photos needed before the slideshow starts; the rest loads in the background.
  static const _initialPhotoCount = 12;

  /// How often the sources are re-scanned for new/removed photos.
  static const _refreshInterval = Duration(minutes: 15);

  /// How long to wait before a refresh or reload that could not run yet (no
  /// engine, or an empty pool), instead of waiting for the next periodic tick.
  static const _retryDelay = Duration(seconds: 60);
  Timer? _retryTimer;

  // Resolved once in `initState` and reused in `dispose`, rather than
  // calling `ref.read(...)` again there: if this whole widget (and its
  // ancestor `ProviderScope`) is torn down in the same frame - e.g. the app
  // root rebuilding with a new `GoRouter` after onboarding completes, or a
  // widget test tearing the tree down - Flutter's element-unmount pass can
  // reach `State.dispose()` after Riverpod has already marked this
  // element's `ref` unusable, and `ref.read` inside `dispose()` throws
  // ("Cannot use 'ref' after the widget was disposed"). Caching the actual
  // controller instances up front sidesteps that ordering hazard entirely,
  // since calling a method on an already-resolved object doesn't touch
  // `ref` at all.
  late final AlwaysOnController _alwaysOnController;
  late final KioskModeController _kioskModeController;

  // Needed so `SlideRenderer` can call `source.fetchToCache(item)` on the
  // right source for the currently displayed item - see _buildEngine().
  Map<String, PhotoSource> _sourcesById = const {};

  // Transition for the "random" setting. Picked once per slide, so rebuilds
  // within the same slide keep the same effect.
  final _transitionPicker = TransitionPicker();
  String? _transitionItemId;
  SlideshowTransition _transitionPick = SlideshowTransition.fade;

  SlideshowTransition _transitionFor(
      SlideshowTransition chosen, String? itemId) {
    if (chosen != SlideshowTransition.random) return chosen;
    if (itemId != _transitionItemId) {
      _transitionItemId = itemId;
      _transitionPick = _transitionPicker.next();
    }
    return _transitionPick;
  }

  @override
  void initState() {
    super.initState();
    // Resolved eagerly (not lazily via `late final = ref.read(...)`) so the
    // very first access can never happen inside `dispose()` itself - see
    // the field-level doc comment above for why that ordering matters.
    _alwaysOnController = ref.read(alwaysOnControllerProvider);
    _kioskModeController = ref.read(kioskModeControllerProvider);
    _ambientSource = ref.read(ambientLightSourceProvider);
    _ambientSub = _ambientSource.lux.listen(_onAmbientLux);
    unawaited(_buildEngine());
    // Fullscreen: hide status and navigation bar while the slideshow runs.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _refreshTimer = Timer.periodic(
        _refreshInterval, (_) => unawaited(_backgroundRefresh()));
  }

  /// Starts or stops the minute timer for the night/dim overlays. Called from
  /// `build`: it only starts or cancels a timer, so it never calls `setState`.
  void _syncMinuteTimer(bool needed) {
    if (needed && _nightTick == null) {
      _nightTick = Timer.periodic(
          const Duration(minutes: 1), (_) => _minuteTick.value++);
    } else if (!needed && _nightTick != null) {
      _nightTick?.cancel();
      _nightTick = null;
    }
  }

  @override
  void dispose() {
    _awaitingPrepared = false;
    _nightTick?.cancel();
    _minuteTick.dispose();
    _ambientSub?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _prefetchSub?.cancel();
    _refreshTimer?.cancel();
    _retryTimer?.cancel();
    final engine = _engine;
    if (engine != null) {
      unawaited(_alwaysOnController.onSlideshowStopped());
      unawaited(_kioskModeController.stop());
      unawaited(engine.dispose());
    }
    super.dispose();
  }

  /// Crawls every source (one broken or hanging source must not block the
  /// others) and applies the playlist filter. Problems are appended to
  /// [errors].
  Future<List<PhotoItem>> _crawlEligible(
    List<PhotoSource> sources,
    AppSettings settings,
    FavoritesStore favorites,
    List<String> errors, {
    int? limit,
    Duration? timeout,
    Set<String>? failedSourceIds,
    Future<void> Function(String sourceId, bool ok, List<PhotoItem> soFar)?
        onSourceDone,
  }) async {
    final allItems = <PhotoItem>[];
    // With [limit] the crawl stops early once that many photos were found, so
    // the slideshow can start while the rest is still being read.
    bool full() => limit != null && allItems.length >= limit;
    final seenKeys = <String>{};
    void collect(PhotoItem item) {
      if (seenKeys.add('${item.sourceId}::${item.id}')) allItems.add(item);
    }

    Future<void> crawl(PhotoSource source) async {
      // `listFolders` only yields *sub*folders, so images lying directly in
      // a source's root folder were never found before. Real sources get an
      // extra non-recursive pass over their root; duplicates are dropped by
      // `seenKeys`.
      if (source.type == SourceType.local ||
          source.type == SourceType.smb ||
          source.type == SourceType.nextcloud ||
          source.type == SourceType.immich) {
        const root = PhotoFolder(id: '', name: '', path: '');
        await for (final r in source.listImages(root, recursive: false)) {
          if (full()) break;
          final item = r.valueOrNull;
          if (item != null) {
            collect(item);
          } else {
            errors.add('${source.displayName}: ${r.failureOrNull?.message}');
          }
        }
      }
      // Folders are visited in random order, so a partial crawl (quick start)
      // draws photos from many folders instead of just the first one.
      final folders = <PhotoFolder>[];
      await for (final folderResult in source.listFolders()) {
        final folder = folderResult.valueOrNull;
        if (folder != null) {
          folders.add(folder);
        } else {
          errors.add(
              '${source.displayName}: ${folderResult.failureOrNull?.message}');
        }
      }
      folders.shuffle(math.Random());
      for (final folder in folders) {
        if (full()) break;
        await for (final itemResult in source.listImages(folder)) {
          if (full()) break;
          final item = itemResult.valueOrNull;
          if (item != null) {
            collect(item);
          } else {
            errors.add(
                '${source.displayName}: ${itemResult.failureOrNull?.message}');
          }
        }
      }
    }

    for (final source in sources) {
      if (full()) break;
      if (settings.disabledSourceIds.contains(source.id)) continue;
      try {
        final run = crawl(source);
        await (timeout == null ? run : run.timeout(timeout));
      } catch (e) {
        errors.add('${source.displayName}: $e');
        // Remembered so a failed or slow source does not wipe its photos from
        // the running pool during a background refresh.
        failedSourceIds?.add(source.id);
      }
      // Reported after every source, so a cancelled or interrupted crawl still
      // leaves a usable index behind.
      await onSourceDone?.call(
        source.id,
        !(failedSourceIds?.contains(source.id) ?? false),
        List.of(allItems),
      );
      // The screen may already be gone while a background crawl runs; `ref` must
      // not be used then.
      if (mounted) {
        ref.read(sourceStatsProvider.notifier).record(
              source.id,
              allItems.where((item) => item.sourceId == source.id).length,
            );
      }
    }
    if (errors.isNotEmpty) {
      debugPrint('Slideshow crawl problems: ${errors.toSet().join(' | ')}');
    }

    // Playlist "favoritesOnly" filter mode: an additional mode on top of
    // "everything from the configured sources"; a no-op when off.
    return _applyFavoritesFilter(allItems, settings, favorites);
  }

  List<PhotoItem> _applyFavoritesFilter(
    List<PhotoItem> items,
    AppSettings settings,
    FavoritesStore favorites,
  ) {
    return applyPlaylistFilter<PhotoItem>(
      items,
      PlaylistFilter(favoritesOnly: settings.favoritesOnlyMode),
      stableIdOf: (item) => item.stableId,
      takenAtOf: (item) => item.takenAt,
      isFavorite: favorites.isFavorite,
    ).toList();
  }

  /// The photos for today: kept for the whole day, redrawn on a new day (see
  /// [DailySelection]). Persisted in shared preferences.
  Future<List<PhotoItem>> _todaysSelection(
      List<PhotoItem> eligible, int count) async {
    final prefs = await ref.read(sharedPreferencesProvider);
    final today = DailySelection.dayKey(DateTime.now());
    String? savedDay;
    var savedKeys = const <String>[];
    final raw = prefs.getString(_dailyKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        savedDay = map['day'] as String?;
        savedKeys = (map['keys'] as List).cast<String>();
      } catch (e, st) {
        // Corrupt value: treat as no saved selection.
        logRecoverableError('Saved daily selection is corrupt',
            error: e, stackTrace: st);
      }
    }
    final chosen = DailySelection.pick<PhotoItem>(
      eligible: eligible,
      keyOf: (item) => '${item.sourceId}::${item.id}',
      count: count,
      today: today,
      savedDay: savedDay,
      savedKeys: savedKeys,
      folderOf: (item) => '${item.sourceId}::${item.folderId}',
    );
    await prefs.setString(
      _dailyKey,
      jsonEncode({
        'day': today,
        'keys': [for (final item in chosen) '${item.sourceId}::${item.id}'],
      }),
    );
    return chosen;
  }

  /// Refreshes the photo list in the background and merges it into the
  /// running engine's pool without interrupting the slideshow.
  ///
  /// Sources are only crawled when the saved index is older than
  /// `AppSettings.indexRefreshHours` (or missing). Otherwise the saved index is
  /// used, so a new day still draws a new selection without touching the
  /// network. Sources that fail keep their photos.
  Future<void> _backgroundRefresh() async {
    final engine = _engine;
    final pool = _pool;
    if (_refreshing) return;
    // No engine yet (or none could be built): nothing to merge into. Try again
    // soon instead of waiting for the screen to be reopened.
    if (engine == null || pool == null) {
      _scheduleRetry();
      return;
    }
    _refreshing = true;
    try {
      final sources = await ref.read(sourcesProvider.future);
      final settings = ref.read(settingsProvider).value ?? const AppSettings();
      final favorites = ref.read(favoritesStoreProvider);
      final store = ref.read(photoIndexStoreProvider);
      final snapshot = await store.load();
      final due = snapshot.items.isEmpty ||
          snapshot.age(DateTime.now()) >=
              Duration(hours: settings.indexRefreshHours);

      final failed = <String>{};
      final List<PhotoItem> eligible;
      if (due) {
        // Sources that succeeded in this crawl; everything else keeps its saved
        // photos.
        final succeeded = <String>{};
        Future<void> persist(List<PhotoItem> soFar) =>
            store.merge(soFar, replacing: succeeded);

        // No timeout here: large network shares can take minutes.
        final crawled = await _crawlEligible(
          sources,
          settings,
          favorites,
          [],
          failedSourceIds: failed,
          onSourceDone: (sourceId, ok, soFar) async {
            if (ok) succeeded.add(sourceId);
            await persist(soFar);
          },
        );
        if (!mounted || _engine != engine) return;
        await persist(crawled);
        eligible = crawled;
      } else {
        final enabledIds = {for (final s in sources) s.id}
          ..removeWhere(settings.disabledSourceIds.contains);
        eligible = _applyFavoritesFilter(
          snapshot.items.where((i) => enabledIds.contains(i.sourceId)).toList(),
          settings,
          favorites,
        );
      }
      if (!mounted || _engine != engine || eligible.isEmpty) return;

      // Prepare a small, screen-sized copy of every photo in small batches.
      if (settings.preparationEnabled) {
        unawaited(ref.read(smallPhotoWorkerProvider.notifier).start(
          (List<PhotoItem>.of(eligible)..shuffle()),
          {for (final s in sources) s.id: s},
        ));
      }

      final fresh = await _preferPrepared(
        await _todaysSelection(eligible, settings.selectionCount),
        index: eligible,
      );
      // Nothing prepared yet (or the wait timed out): keep the photos already in
      // the pool rather than emptying it.
      if (fresh.isEmpty || !mounted || _engine != engine) return;
      final freshKeys = {for (final i in fresh) '${i.sourceId}::${i.id}'};
      bool kept(String sourceId, String itemId) =>
          failed.contains(sourceId) || freshKeys.contains('$sourceId::$itemId');
      for (final e in pool.entries) {
        if (!kept(e.sourceId, e.itemId)) pool.remove(e.sourceId, e.itemId);
      }
      for (final item in fresh) {
        _itemsByKey['${item.sourceId}::${item.id}'] = item;
        pool.add(PoolEntry(
            sourceId: item.sourceId,
            itemId: item.id,
            addedToPoolAt: DateTime.now()));
      }
      _itemsByKey.removeWhere((_, item) => !kept(item.sourceId, item.id));
      if (pool.entries.isNotEmpty) engine.refreshPool(pool);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    } finally {
      _refreshing = false;
      // An empty pool is refreshed again soon, not only at the next periodic
      // refresh.
      if (mounted && _engine == engine && pool.entries.isEmpty) {
        _scheduleRetry();
      }
    }
  }

  /// Runs [_onRetry] once after [_retryDelay], replacing a pending retry.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () => unawaited(_onRetry()));
  }

  /// Refreshes a running engine, or rebuilds a screen that shows the empty state
  /// because no engine could be built. A failed load keeps its own retry button.
  Future<void> _onRetry() async {
    if (!mounted) return;
    if (_engine != null) {
      await _backgroundRefresh();
      return;
    }
    if (_loadError != null) return;
    if (_loading) {
      // A load is still running; check again later.
      _scheduleRetry();
      return;
    }
    setState(() => _loading = true);
    await _buildEngine();
  }

  /// Downloads one more photo from a network source while the current one is
  /// on screen, so the next network photo is already in the cache when it is
  /// due. Local photos need no download and are skipped.
  void _prefetchNext() {
    // Prefetching goes through the worker too, so it is skipped with it.
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    if (!settings.preparationEnabled) return;
    final candidates = _itemsByKey.values.where((item) {
      final source = _sourcesById[item.sourceId];
      return source != null &&
          (source.type == SourceType.smb ||
              source.type == SourceType.nextcloud ||
              source.type == SourceType.immich);
    }).toList();
    if (candidates.isEmpty) return;
    final item = candidates[_prefetchRandom.nextInt(candidates.length)];
    final source = _sourcesById[item.sourceId];
    if (source == null) return;
    // Goes through the worker's queue (at the front), so it never runs in
    // parallel with the worker's own scaling. Failures are ignored: the photo
    // is fetched again when it is shown.
    unawaited(ref
        .read(smallPhotoWorkerProvider.notifier)
        .prioritize(item, source)
        .then<void>((_) {}, onError: (Object _) {}));
  }

  /// Picks the photos to start with, in this order:
  ///
  /// 1. The prepared photos of [items] (today's selection).
  /// 2. If none of them is prepared, the prepared photos of [index] (the whole
  ///    photo index). The worker prepares photos in random order, so the
  ///    prepared copies may lie outside the selection.
  /// 3. Only if nothing is prepared anywhere, wait for the worker to finish the
  ///    first copies, up to `preparedWaitLimit` (3 minutes by default).
  ///
  /// Without an [index] only steps 1 and 3 apply, for [items]. Raw downloads
  /// are used only when `onlyPreparedPhotos` is off: then the photos of [items]
  /// are returned when nothing is prepared anywhere. Preparation off counts as
  /// `onlyPreparedPhotos` off (see `AppSettings.onlyPreparedRuleActive`).
  Future<List<PhotoItem>> _preferPrepared(
    List<PhotoItem> items, {
    List<PhotoItem> index = const [],
  }) async {
    final cache = ref.read(smallPhotoCacheProvider);
    // False while preparation is off: raw downloads are then shown, and the
    // start does not wait for prepared copies.
    final onlyPrepared =
        (ref.read(settingsProvider).value ?? const AppSettings())
            .onlyPreparedRuleActive;
    Future<List<PhotoItem>> preparedIn(List<PhotoItem> candidates) async {
      final list = <PhotoItem>[];
      for (final item in candidates) {
        if (await cache.existing(item) != null) list.add(item);
      }
      return list;
    }

    Future<List<PhotoItem>> prepared() async {
      final selected = await preparedIn(items);
      if (selected.isNotEmpty) return selected;
      return preparedIn(index);
    }

    var list = await prepared();
    if (!onlyPrepared) return list.isEmpty ? items : list;
    // Only checked small copies are shown. While none exists yet, wait for the
    // worker to finish the first ones (up to `preparedWaitLimit`, 3 minutes by
    // default) instead of showing raw downloads.
    final deadline = DateTime.now().add(widget.preparedWaitLimit);
    while (list.isEmpty && mounted && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final status = ref.read(smallPhotoWorkerProvider);
      if (status.done > 0 || !status.running) list = await prepared();
    }
    return list;
  }

  /// Runs [_preferPrepared] for the start path with [_awaitingPrepared] set, so
  /// the preparing view shows while the start waits. The flag is cleared in
  /// `finally`, so it is reset whether the wait returns, throws, or the screen
  /// is already gone. The engine is not built yet at this point, so the screen
  /// keeps its loading state until the engine is set.
  Future<List<PhotoItem>> _awaitPreparedAtStart(
    List<PhotoItem> items, {
    required List<PhotoItem> index,
  }) async {
    _setAwaitingPrepared(true);
    try {
      return await _preferPrepared(items, index: index);
    } finally {
      _setAwaitingPrepared(false);
    }
  }

  void _setAwaitingPrepared(bool value) {
    if (_awaitingPrepared == value) return;
    if (mounted) {
      setState(() => _awaitingPrepared = value);
    } else {
      _awaitingPrepared = value;
    }
  }

  /// Handles a photo that cannot be shown.
  ///
  /// A photo whose small copy is not prepared yet stays in the pool: the
  /// slideshow's timer moves on, and the photo comes up again on a later turn,
  /// by which time the copy may exist. A photo that cannot be read at all is
  /// taken out of the pool, and the slideshow moves on to the next one.
  void _skipUnavailable(PhotoItem item, SlideUnavailableReason reason) {
    final pool = _pool;
    final engine = _engine;
    if (pool == null || engine == null) return;
    // A late result for a photo that is no longer on screen: ignore it.
    final current = engine.currentItem;
    if (current == null ||
        current.sourceId != item.sourceId ||
        current.id != item.id) {
      return;
    }
    if (reason == SlideUnavailableReason.notPreparedYet) return;

    pool.remove(item.sourceId, item.id);
    _itemsByKey.remove('${item.sourceId}::${item.id}');
    if (pool.entries.isEmpty) {
      // Nothing left to show: the empty state is shown (see `build`). The
      // engine is not given an empty list (ShuffleBag rejects it).
      setState(() {});
      return;
    }
    engine.refreshPool(pool);
    _next();
  }

  Future<void> _buildEngine() async {
    // Awaited: the cache must be empty before the first photo is downloaded.
    await ref.read(networkCacheCleanerProvider)();
    try {
      // `sourcesProvider` now loads its descriptor list (and re-attaches
      // credentials) from storage asynchronously - see
      // `SourcesController.build`. Awaiting `.future` here (rather than
      // `ref.read`) blocks this screen's own loading state on that instead
      // of racing it with an empty/stale source list; a load failure is
      // caught below just like an engine-build failure, surfacing the same
      // "loading failed" state instead of crashing unhandled.
      final sources = await ref.read(sourcesProvider.future);
      if (!mounted) return;
      final settings = ref.read(settingsProvider).value ?? const AppSettings();
      final favorites = ref.read(favoritesStoreProvider);

      final pool = InMemoryWorkingSetPool(targetSize: settings.poolTargetSize);
      final itemsByKey = <String, PhotoItem>{};
      final sourcesById = {for (final s in sources) s.id: s};
      final errors = <String>[];

      // Start with the first ~12 photos, then read the rest in the background
      // (see the refresh call after the engine has started).
      // A saved index (see PhotoIndexStore) gives a full photo list at once;
      // without one, start with the first photos found by a crawl.
      final snapshot = await ref.read(photoIndexStoreProvider).load();
      final indexed = snapshot.items
          .where((i) =>
              sourcesById.containsKey(i.sourceId) &&
              !settings.disabledSourceIds.contains(i.sourceId))
          .toList();
      final List<PhotoItem> eligibleItems;
      if (indexed.isNotEmpty) {
        final candidates = _applyFavoritesFilter(indexed, settings, favorites);
        eligibleItems = await _awaitPreparedAtStart(
          await _todaysSelection(candidates, settings.selectionCount),
          index: candidates,
        );
      } else {
        eligibleItems = await _crawlEligible(
          sources,
          settings,
          favorites,
          errors,
          limit: _initialPhotoCount,
          timeout: const Duration(seconds: 30),
        );
      }
      for (final item in eligibleItems) {
        itemsByKey['${item.sourceId}::${item.id}'] = item;
        pool.add(PoolEntry(
          sourceId: item.sourceId,
          itemId: item.id,
          addedToPoolAt: DateTime.now(),
        ));
      }

      if (!mounted) return;

      if (pool.entries.isEmpty) {
        final previous = _engine;
        setState(() {
          _engine = null;
          _loadError = errors.isEmpty ? null : errors.toSet().join('\n');
          _loading = false;
        });
        unawaited(previous?.dispose());
        return;
      }

      // Must be filled before `engine.start()`: it resolves the first item
      // through `_itemsByKey` immediately.
      _pool = pool;
      _itemsByKey
        ..clear()
        ..addAll(itemsByKey);
      final engine = SlideshowEngine(
        pool: pool,
        sources: sourcesById,
        resolveItem: (entry) async =>
            _itemsByKey['${entry.sourceId}::${entry.itemId}'],
        config: settings.toSlideshowConfig(),
      );
      await engine.start();
      if (!mounted) {
        await engine.dispose();
        return;
      }
      final previous = _engine;
      setState(() {
        _engine = engine;
        _prefetchSub?.cancel();
        _prefetchSub = engine.currentItemChanges.listen((_) => _prefetchNext());
        _sourcesById = sourcesById;
        _loading = false;
      });
      // A reload from the empty state replaces a running engine.
      unawaited(previous?.dispose());
      // Read the remaining photos in the background; the pool is merged in
      // without interrupting the running slideshow.
      unawaited(_backgroundRefresh());
      await _alwaysOnController.onSlideshowStarted();
      // Kiosk/Autostart (ADR-004): only pin the screen when the user opted
      // in via kiosk_settings_screen.dart - see KioskModeController's doc
      // comment for why this is safe to call unconditionally on unsupported
      // platforms (silently no-ops there).
      if (settings.kioskModeEnabled) {
        await _kioskModeController.start();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// "Quelle › Pfad" plus capture date (EXIF) or, failing that, file date.
  String _originText(PhotoItem item) {
    final source = _sourcesById[item.sourceId]?.displayName ?? item.sourceId;
    final taken = item.takenAt;
    final date = taken ?? item.mtime;
    String two(int v) => v.toString().padLeft(2, '0');
    final label = '${two(date.day)}.${two(date.month)}.${date.year}';
    final when = taken != null ? 'Aufgenommen $label' : 'Datei vom $label';
    final slash = item.id.lastIndexOf('/');
    final folder = slash > 0 ? item.id.substring(0, slash) : '/';
    return '$source \u203a $folder\n$when';
  }

  void _onAmbientLux(double lux) {
    final opacity = _ambientDim.update(lux);
    if (mounted && opacity != _sensorDimOpacity) {
      setState(() => _sensorDimOpacity = opacity);
    }
  }

  void _togglePause() {
    final engine = _engine;
    if (engine == null) return;
    if (_paused) {
      unawaited(engine.start());
    } else {
      engine.stop();
    }
    setState(() => _paused = !_paused);
  }

  /// The photos for a 2x2 grid: the current one plus three more from the
  /// pool, chosen deterministically from the current photo so the grid does
  /// not flicker while it is shown.
  List<PhotoItem> _gridItems(PhotoItem first) {
    final others = _itemsByKey.values
        .where((i) => i.stableId != first.stableId)
        .toList()
      ..shuffle(math.Random(first.stableId.hashCode));
    if (others.length < 3) return [first];
    return [first, ...others.take(3)];
  }

  void _previous() {
    final engine = _engine;
    if (engine != null) unawaited(engine.showPrevious());
  }

  void _next() {
    final engine = _engine;
    if (engine != null) unawaited(engine.skipToNext());
  }

  void _showInfo(PhotoItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bildinformation'),
        content: Text(
          'Name: ${item.name}\n'
          'Quelle: ${item.sourceId}\n'
          'Größe: ${(item.size / 1024).round()} KB\n'
          'Aufgenommen: ${item.takenAt ?? 'unbekannt'}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Schließen')),
        ],
      ),
    );
  }

  /// Opens the settings and, once they are closed again, rebuilds the engine
  /// so added/removed sources and changed pool/filter settings take effect
  /// (the engine used to be built exactly once). The slideshow is paused
  /// while the settings are open instead of silently fetching in the
  /// background.
  Future<void> _pushSettings() async {
    _engine?.stop();
    await context.push('/settings');
    if (!mounted) return;
    final old = _engine;
    setState(() {
      _engine = null;
      _loadError = null;
      _paused = false;
      _loading = true;
    });
    if (old != null) {
      unawaited(_alwaysOnController.onSlideshowStopped());
      await old.dispose();
    }
    if (mounted) await _buildEngine();
  }

  Future<void> _openSettings(String? pin) async {
    if (pin == null || pin.isEmpty) {
      if (mounted) unawaited(_pushSettings());
      return;
    }
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PIN eingeben'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text == pin),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      unawaited(_pushSettings());
    } else if (ok == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falscher PIN')),
      );
    }
  }

  /// Night dimming and the ambient time-window dim. Evaluated against the
  /// current time on every minute tick (see `_minuteTick`).
  Widget _buildDimLayers(AppSettings settings) {
    final now = DateTime.now();
    final isNight = settings.nightSchedule.isNightAt(now);
    final inDimWindow = isWithinDimWindow(
      now,
      startMinutes: settings.dimStartMinutes,
      endMinutes: settings.dimEndMinutes,
    );
    final hasLightSensor = _ambientSource is! NoopAmbientLightSource;
    final ambientDimOpacity = !inDimWindow
        ? 0.0
        : hasLightSensor
            ? _sensorDimOpacity
            : _fixedAmbientDimOpacity;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Ambient dimming: black overlay inside the configured time window.
        // Without a light sensor the fixed opacity applies; with one, the
        // lux-based opacity is used instead. The AnimatedOpacity fades in and
        // out over the whole window edge.
        if (settings.ambientDimEnabled)
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: ambientDimOpacity,
              duration: const Duration(seconds: 2),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        if (isNight)
          IgnorePointer(
            child: Container(
              color: Colors.black
                  .withValues(alpha: settings.nightSchedule.dimAmount),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    // While the start waits for prepared copies, the engine-null branch below
    // shows the preparing view (with the same action buttons) instead.
    if (_loading && !_awaitingPrepared) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Center(child: CircularProgressIndicator()),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: IconButton(
                  tooltip: 'Einstellungen',
                  color: Colors.white70,
                  icon: const Icon(Icons.settings),
                  onPressed: () =>
                      _openSettings(settingsAsync.value?.settingsPin),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Fehler beim Laden der Diashow:\n$_loadError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _loadError = null;
                      _loading = true;
                    });
                    unawaited(_buildEngine());
                  },
                  child: const Text('Erneut versuchen'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () =>
                      _openSettings(settingsAsync.value?.settingsPin),
                  child: const Text('Einstellungen'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final engine = _engine;
    // An emptied pool shows the same state as no engine at all.
    final poolEmpty = _pool == null || _pool!.entries.isEmpty;
    if (engine == null || poolEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Same action buttons either way; only the content changes.
          _awaitingPrepared ? const PreparingView() : const EmptyStateView(),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Neu laden',
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      setState(() => _loading = true);
                      unawaited(_buildEngine());
                    },
                  ),
                  IconButton(
                    tooltip: 'Einstellungen',
                    icon: const Icon(Icons.settings),
                    onPressed: () =>
                        _openSettings(settingsAsync.value?.settingsPin),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final settings = settingsAsync.value ?? const AppSettings();
    _syncMinuteTimer(
      settings.nightSchedule.mode != NightScheduleMode.disabled ||
          settings.ambientDimEnabled,
    );
    final favorites = ref.watch(favoritesStoreProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: TouchControlOverlay(
        isPaused: _paused,
        onTogglePause: _togglePause,
        onNext: _next,
        onPrevious: _previous,
        onShowInfo: () {
          final item = engine.currentItem;
          if (item != null) _showInfo(item);
        },
        onOpenSettings: () => _openSettings(settings.settingsPin),
        onHome: () => context.go('/'),
        isFavorite: engine.currentItem != null &&
            favorites.isFavorite(engine.currentItem!.stableId),
        onToggleFavorite: engine.currentItem == null
            ? null
            : () => favorites.toggleFavorite(engine.currentItem!.stableId),
        child: StreamBuilder<PhotoItem?>(
          stream: engine.currentItemChanges,
          initialData: engine.currentItem,
          builder: (context, snapshot) {
            final item = snapshot.data;
            // "Bewegung reduzieren" (system accessibility signal) forces
            // transition=none and Ken Burns off regardless of the user's
            // settings - see EffectiveVisualSettings' doc comment.
            final reduceMotion = MediaQuery.of(context).disableAnimations;
            final effective = EffectiveVisualSettings.resolve(
              transition: _transitionFor(settings.transition, item?.id),
              kenBurnsEnabled: settings.kenBurnsEnabled,
              reduceMotion: reduceMotion,
            );

            final itemSource =
                item == null ? null : _sourcesById[item.sourceId];
            Widget slide = (item == null || itemSource == null)
                ? const SizedBox.shrink(key: ValueKey('empty'))
                : settings.slideLayout == SlideLayout.grid2x2
                    ? _GridSlide(
                        items: _gridItems(item),
                        sourcesById: _sourcesById,
                        displayMode: settings.displayMode,
                      )
                    : SlideRenderer(
                        item: item,
                        source: itemSource,
                        displayMode: settings.displayMode,
                        onUnavailable: (reason) =>
                            _skipUnavailable(item, reason),
                      );
            if (item != null && effective.kenBurnsEnabled) {
              slide = KenBurnsEffect(
                key: ValueKey(item.id),
                duration: settings.interval,
                child: slide,
              );
            } else if (item != null) {
              slide = KeyedSubtree(key: ValueKey(item.id), child: slide);
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: effective.transition == SlideshowTransition.none
                      ? Duration.zero
                      : const Duration(milliseconds: 600),
                  transitionBuilder: (child, animation) {
                    switch (effective.transition) {
                      case SlideshowTransition.random:
                      // Resolved to a concrete effect in _transitionFor.
                      case SlideshowTransition.none:
                        // Instant swap, no animated transition at all.
                        return child;
                      case SlideshowTransition.fade:
                        return FadeTransition(opacity: animation, child: child);
                      case SlideshowTransition.slide:
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        );
                      case SlideshowTransition.slideUp:
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          )),
                          child: child,
                        );
                      case SlideshowTransition.blurFade:
                        // Fades in while sharpening from a blurred start.
                        return FadeTransition(
                          opacity: animation,
                          child: AnimatedBuilder(
                            animation: animation,
                            builder: (context, child) => ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: (1 - animation.value) * 18,
                                sigmaY: (1 - animation.value) * 18,
                              ),
                              child: child,
                            ),
                            child: child,
                          ),
                        );
                      case SlideshowTransition.flip:
                        // Turns around the vertical axis, like a card.
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            final angle = (1 - animation.value) * math.pi / 2;
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..rotateY(angle),
                              child: child,
                            );
                          },
                          child: child,
                        );
                      case SlideshowTransition.zoom:
                        // New photo grows from 92% and fades in together.
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.92, end: 1).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                            child: child,
                          ),
                        );
                    }
                  },
                  child: slide,
                ),
                // Thin, subtle bar that runs down over one interval, so it is
                // visible when the next photo is due. Restarts per photo
                // (keyed by item id) and is hidden while paused.
                if (item != null && !_paused)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey('progress-${item.sourceId}-${item.id}'),
                        tween: Tween(begin: 0, end: 1),
                        duration: settings.interval,
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ),
                if (settings.showImageDetails && item != null)
                  PathOverlay(
                    text: _originText(item),
                    onRight: settings.imageDetailsOnRight,
                  ),
                if (settings.showSourceLabel && item != null)
                  SourceLabelOverlay(label: item.sourceId),
                // The path overlay already shows the date, so the caption is only
                // needed when the path overlay is off.
                if (settings.showCaptionOverlay &&
                    !settings.showImageDetails &&
                    item != null)
                  CaptionOverlay(
                    text: captionTextFor(item),
                    // Weather is always bottom-left; the clock only when it
                    // is not moved to the top.
                    raised: settings.weatherEnabled ||
                        (settings.showClock && !settings.clockAtTop),
                  ),
                // Clock and weather share the bottom-left corner: shown
                // combined in one pill when both are enabled, otherwise
                // whichever one is enabled renders alone. See
                // WeatherOverlayContent's doc comment for the full
                // positioning rationale.
                if (settings.showClock && settings.weatherEnabled)
                  Positioned(
                    left: 16,
                    top: settings.clockAtTop ? 16 : null,
                    bottom: settings.clockAtTop ? null : 16,
                    child: const InfoBarPill(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClockText(),
                          SizedBox(width: 10),
                          _InfoBarDivider(),
                          SizedBox(width: 10),
                          WeatherOverlayContent(),
                        ],
                      ),
                    ),
                  )
                else if (settings.showClock)
                  ClockOverlay(atTop: settings.clockAtTop)
                else if (settings.weatherEnabled)
                  const WeatherOverlay(),
                // Ambient dimming: black overlay inside the configured time
                // window. Without a light sensor the fixed opacity applies;
                // with one, the lux-based opacity is used instead. The
                // AnimatedOpacity fades in and out over the whole window edge.
                if (settings.ambientDimEnabled ||
                    settings.nightSchedule.mode != NightScheduleMode.disabled)
                  Positioned.fill(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _minuteTick,
                      builder: (context, _, __) => _buildDimLayers(settings),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tiny visual separator between the clock and weather content in the
/// combined bottom-left info-bar pill (see [_SlideshowScreenState.build]).
class _InfoBarDivider extends StatelessWidget {
  const _InfoBarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 16, color: Colors.white38);
  }
}

/// Four photos in a 2x2 grid, each cropped to fill its cell.
class _GridSlide extends StatelessWidget {
  const _GridSlide({
    required this.items,
    required this.sourcesById,
    required this.displayMode,
  });

  final List<PhotoItem> items;
  final Map<String, PhotoSource> sourcesById;
  final DisplayMode displayMode;

  @override
  Widget build(BuildContext context) {
    if (items.length < 4) {
      final only = items.first;
      final source = sourcesById[only.sourceId];
      if (source == null) return const SizedBox.shrink();
      return SlideRenderer(
          item: only, source: source, displayMode: displayMode);
    }
    Widget cell(PhotoItem item) {
      final source = sourcesById[item.sourceId];
      if (source == null) return const ColoredBox(color: Colors.black);
      return ClipRect(
        child: SlideRenderer(
          key: ValueKey('grid-${item.stableId}'),
          item: item,
          source: source,
          displayMode: DisplayMode.cover,
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: Row(children: [
              Expanded(child: cell(items[0])),
              const SizedBox(width: 4),
              Expanded(child: cell(items[1])),
            ]),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(children: [
              Expanded(child: cell(items[2])),
              const SizedBox(width: 4),
              Expanded(child: cell(items[3])),
            ]),
          ),
        ],
      ),
    );
  }
}
