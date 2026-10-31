import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/kiosk/kiosk_mode_controller.dart';
import '../../favorites/domain/favorites_store.dart';
import '../../favorites/state/favorites_providers.dart';
import '../../index/working_set_pool.dart';
import '../../playlists/playlist.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_providers.dart';
import '../../sources/domain/photo_folder.dart';
import '../../sources/domain/photo_item.dart';
import '../../sources/state/source_stats.dart';
import '../../sources/domain/photo_source.dart';
import '../../sources/state/sources_providers.dart';
import '../domain/always_on_controller.dart';
import '../domain/effective_visual_settings.dart';
import '../domain/slideshow_config.dart';
import '../domain/slideshow_engine.dart';
import '../state/slideshow_providers.dart';
import 'widgets/clock_overlay.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/ken_burns_effect.dart';
import 'widgets/slide_renderer.dart';
import 'widgets/path_overlay.dart';
import 'widgets/source_label_overlay.dart';
import 'widgets/touch_control_overlay.dart';
import 'widgets/weather_overlay.dart';

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
  const SlideshowScreen({super.key});

  @override
  ConsumerState<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends ConsumerState<SlideshowScreen> {
  SlideshowEngine? _engine;
  bool _paused = false;
  bool _loading = true;
  Object? _loadError;
  Timer? _nightTick;
  Timer? _refreshTimer;
  InMemoryWorkingSetPool? _pool;
  final Map<String, PhotoItem> _itemsByKey = {};
  bool _refreshing = false;

  /// How often the sources are re-scanned for new/removed photos.
  static const _refreshInterval = Duration(minutes: 15);

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

  @override
  void initState() {
    super.initState();
    // Resolved eagerly (not lazily via `late final = ref.read(...)`) so the
    // very first access can never happen inside `dispose()` itself - see
    // the field-level doc comment above for why that ordering matters.
    _alwaysOnController = ref.read(alwaysOnControllerProvider);
    _kioskModeController = ref.read(kioskModeControllerProvider);
    unawaited(_buildEngine());
    _refreshTimer = Timer.periodic(
        _refreshInterval, (_) => unawaited(_backgroundRefresh()));
    _nightTick =
        Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _nightTick?.cancel();
    _refreshTimer?.cancel();
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
    List<String> errors,
  ) async {
    final allItems = <PhotoItem>[];
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
          source.type == SourceType.nextcloud) {
        const root = PhotoFolder(id: '', name: '', path: '');
        await for (final r in source.listImages(root, recursive: false)) {
          final item = r.valueOrNull;
          if (item != null) {
            collect(item);
          } else {
            errors.add('${source.displayName}: ${r.failureOrNull?.message}');
          }
        }
      }
      await for (final folderResult in source.listFolders()) {
        final folder = folderResult.valueOrNull;
        if (folder == null) {
          errors.add(
              '${source.displayName}: ${folderResult.failureOrNull?.message}');
          continue;
        }
        await for (final itemResult in source.listImages(folder)) {
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
      if (settings.disabledSourceIds.contains(source.id)) continue;
      try {
        await crawl(source).timeout(const Duration(seconds: 90));
      } catch (e) {
        errors.add('${source.displayName}: $e');
      }
      ref.read(sourceStatsProvider.notifier).record(
            source.id,
            allItems.where((item) => item.sourceId == source.id).length,
          );
    }
    if (errors.isNotEmpty) {
      debugPrint('Slideshow crawl problems: ${errors.toSet().join(' | ')}');
    }

    // Playlist "favoritesOnly" filter mode: an additional mode on top of
    // "everything from the configured sources"; a no-op when off.
    return applyPlaylistFilter<PhotoItem>(
      allItems,
      PlaylistFilter(favoritesOnly: settings.favoritesOnlyMode),
      stableIdOf: (item) => item.stableId,
      takenAtOf: (item) => item.takenAt,
      isFavorite: favorites.isFavorite,
    ).toList();
  }

  /// Re-crawls the sources in the background and merges the result into the
  /// running engine's pool (new photos added, vanished ones dropped) without
  /// interrupting the slideshow. A crawl that finds nothing (e.g. network
  /// down) never wipes the current pool.
  Future<void> _backgroundRefresh() async {
    final engine = _engine;
    final pool = _pool;
    if (_refreshing || engine == null || pool == null) return;
    _refreshing = true;
    try {
      final sources = await ref.read(sourcesProvider.future);
      final settings = ref.read(settingsProvider).value ?? const AppSettings();
      final fresh = await _crawlEligible(
          sources, settings, ref.read(favoritesStoreProvider), []);
      if (!mounted || _engine != engine || fresh.isEmpty) return;
      final freshKeys = {for (final i in fresh) '${i.sourceId}::${i.id}'};
      for (final e in pool.entries) {
        if (!freshKeys.contains(e.key)) pool.remove(e.sourceId, e.itemId);
      }
      for (final item in fresh) {
        _itemsByKey['${item.sourceId}::${item.id}'] = item;
        pool.add(PoolEntry(
            sourceId: item.sourceId,
            itemId: item.id,
            addedToPoolAt: DateTime.now()));
      }
      _itemsByKey.removeWhere((k, _) => !freshKeys.contains(k));
      if (pool.entries.isNotEmpty) engine.refreshPool(pool);
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _buildEngine() async {
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

      final eligibleItems =
          await _crawlEligible(sources, settings, favorites, errors);
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
        setState(() {
          _loadError = errors.isEmpty ? null : errors.toSet().join('\n');
          _loading = false;
        });
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
      setState(() {
        _engine = engine;
        _sourcesById = sourcesById;
        _loading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    if (_loading) {
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
    if (engine == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const EmptyStateView(),
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
    final isNight = settings.nightSchedule.isNightAt(DateTime.now());
    final favorites = ref.watch(favoritesStoreProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: TouchControlOverlay(
        isPaused: _paused,
        onTogglePause: _togglePause,
        onNext: _next,
        onShowInfo: () {
          final item = engine.currentItem;
          if (item != null) _showInfo(item);
        },
        onOpenSettings: () => _openSettings(settings.settingsPin),
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
            final effective = EffectiveVisualSettings.fromSettings(
              settings,
              reduceMotion: reduceMotion,
            );

            final itemSource =
                item == null ? null : _sourcesById[item.sourceId];
            Widget slide = (item == null || itemSource == null)
                ? const SizedBox.shrink(key: ValueKey('empty'))
                : SlideRenderer(
                    item: item,
                    source: itemSource,
                    displayMode: settings.displayMode,
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
                // Clock and weather share the bottom-left corner: shown
                // combined in one pill when both are enabled, otherwise
                // whichever one is enabled renders alone. See
                // WeatherOverlayContent's doc comment for the full
                // positioning rationale.
                if (settings.showClock && settings.weatherEnabled)
                  const Positioned(
                    left: 16,
                    bottom: 16,
                    child: InfoBarPill(
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
                  const ClockOverlay()
                else if (settings.weatherEnabled)
                  const WeatherOverlay(),
                if (isNight)
                  IgnorePointer(
                    child: Container(
                      color: Colors.black
                          .withValues(alpha: settings.nightSchedule.dimAmount),
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
