import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../index/working_set_pool.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_providers.dart';
import '../../sources/domain/photo_item.dart';
import '../../sources/domain/photo_source.dart';
import '../../sources/state/sources_providers.dart';
import '../domain/slideshow_config.dart';
import '../domain/slideshow_engine.dart';
import '../state/slideshow_providers.dart';
import 'widgets/clock_overlay.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/slide_renderer.dart';
import 'widgets/source_label_overlay.dart';
import 'widgets/touch_control_overlay.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(_buildEngine());
    _nightTick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _nightTick?.cancel();
    final engine = _engine;
    if (engine != null) {
      unawaited(ref.read(alwaysOnControllerProvider).onSlideshowStopped());
      unawaited(engine.dispose());
    }
    super.dispose();
  }

  Future<void> _buildEngine() async {
    final sources = ref.read(sourcesProvider);
    final settings = ref.read(settingsProvider).valueOrNull ?? const AppSettings();

    final pool = InMemoryWorkingSetPool(targetSize: settings.poolTargetSize);
    final itemsByKey = <String, PhotoItem>{};
    final sourcesById = <String, PhotoSource>{};

    for (final source in sources) {
      sourcesById[source.id] = source;
      await for (final folderResult in source.listFolders()) {
        final folder = folderResult.valueOrNull;
        if (folder == null) continue;
        await for (final itemResult in source.listImages(folder)) {
          final item = itemResult.valueOrNull;
          if (item == null) continue;
          itemsByKey['${item.sourceId}::${item.id}'] = item;
          pool.add(PoolEntry(
            sourceId: item.sourceId,
            itemId: item.id,
            addedToPoolAt: DateTime.now(),
          ));
        }
      }
    }

    if (!mounted) return;

    if (pool.entries.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    try {
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
      await ref.read(alwaysOnControllerProvider).onSlideshowStarted();
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
        child: StreamBuilder<PhotoItem?>(
          stream: engine.currentItemChanges,
          initialData: engine.currentItem,
          builder: (context, snapshot) {
            final item = snapshot.data;
            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: settings.transition == SlideshowTransition.none
                      ? Duration.zero
                      : const Duration(milliseconds: 600),
                  transitionBuilder: (child, animation) {
                    switch (settings.transition) {
                      case SlideshowTransition.fade:
                      case SlideshowTransition.none:
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
                  child: item == null
                      ? const SizedBox.shrink(key: ValueKey('empty'))
                      : SlideRenderer(
                          key: ValueKey(item.id),
                          item: item,
                          displayMode: settings.displayMode,
                        ),
                ),
                if (settings.showSourceLabel && item != null)
                  SourceLabelOverlay(label: item.sourceId),
                if (settings.showClock) const ClockOverlay(),
                if (isNight)
                  IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity(settings.nightSchedule.dimAmount),
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
