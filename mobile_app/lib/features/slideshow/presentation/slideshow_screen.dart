import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/kiosk/kiosk_mode_controller.dart';
import '../../favorites/state/favorites_providers.dart';
import '../../index/working_set_pool.dart';
import '../../playlists/playlist.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_providers.dart';
import '../../sources/domain/photo_item.dart';
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

  @override
  void initState() {
    super.initState();
    // Resolved eagerly (not lazily via `late final = ref.read(...)`) so the
    // very first access can never happen inside `dispose()` itself - see
    // the field-level doc comment above for why that ordering matters.
    _alwaysOnController = ref.read(alwaysOnControllerProvider);
    _kioskModeController = ref.read(kioskModeControllerProvider);
    unawaited(_buildEngine());
    _nightTick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _nightTick?.cancel();
    final engine = _engine;
    if (engine != null) {
      unawaited(_alwaysOnController.onSlideshowStopped());
      unawaited(_kioskModeController.stop());
      unawaited(engine.dispose());
    }
    super.dispose();
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
      final settings = ref.read(settingsProvider).valueOrNull ?? const AppSettings();
      final favorites = ref.read(favoritesStoreProvider);

      final pool = InMemoryWorkingSetPool(targetSize: settings.poolTargetSize);
      final itemsByKey = <String, PhotoItem>{};
      final sourcesById = <String, PhotoSource>{};
      final allItems = <PhotoItem>[];

      for (final source in sources) {
        sourcesById[source.id] = source;
        await for (final folderResult in source.listFolders()) {
          final folder = folderResult.valueOrNull;
          if (folder == null) continue;
          await for (final itemResult in source.listImages(folder)) {
            final item = itemResult.valueOrNull;
            if (item == null) continue;
            allItems.add(item);
          }
        }
      }

      // Playlist "favoritesOnly" filter mode (see docs/PLAN.md playlist
      // model and `AppSettings.favoritesOnlyMode`): an *additional* mode on
      // top of the default "everything from the configured sources"
      // behaviour below, not a replacement for it - when off,
      // `applyPlaylistFilter` is a no-op and every crawled item is admitted
      // exactly as before this feature.
      final filter = PlaylistFilter(favoritesOnly: settings.favoritesOnlyMode);
      final eligibleItems = applyPlaylistFilter<PhotoItem>(
        allItems,
        filter,
        stableIdOf: (item) => item.stableId,
        takenAtOf: (item) => item.takenAt,
        isFavorite: favorites.isFavorite,
      );

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
        setState(() => _loading = false);
        return;
      }

      final engine = SlideshowEngine(
        pool: pool,
        sources: sourcesById,
        resolveItem: (entry) async => itemsByKey['${entry.sourceId}::${entry.itemId}'],
        config: settings.toSlideshowConfig(),
      );
      await engine.start();
      if (!mounted) {
        await engine.dispose();
        return;
      }
      setState(() {
        _engine = engine;
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
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Schließen')),
        ],
      ),
    );
  }

  Future<void> _openSettings(String? pin) async {
    if (pin == null || pin.isEmpty) {
      if (mounted) unawaited(context.push('/settings'));
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
      unawaited(context.push('/settings'));
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
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('Fehler beim Laden der Diashow: $_loadError',
              style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final engine = _engine;
    if (engine == null) {
      return const EmptyStateView();
    }

    final settings = settingsAsync.valueOrNull ?? const AppSettings();
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

            Widget slide = item == null
                ? const SizedBox.shrink(key: ValueKey('empty'))
                : SlideRenderer(
                    item: item,
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
                    }
                  },
                  child: slide,
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
                      color: Colors.black.withValues(alpha: settings.nightSchedule.dimAmount),
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
