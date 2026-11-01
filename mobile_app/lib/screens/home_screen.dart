import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/utils/app_log.dart';
import '../features/cache/small_photo_cache.dart';
import '../features/cache/small_photo_usage_provider.dart';
import '../features/index/photo_index_store.dart';
import '../features/settings/state/settings_providers.dart';
import '../features/sources/domain/photo_item.dart';
import '../features/sources/domain/photo_source.dart';
import '../features/sources/state/sources_providers.dart';

/// Start screen: a background photo from the index, the current status of
/// sources, index and preparation, and the main actions.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final SmallPhotoWorker _worker;

  /// `true` when this screen started the worker run, so only this screen's
  /// run is stopped when it is disposed.
  bool _startedRun = false;

  @override
  void initState() {
    super.initState();
    _worker = ref.read(smallPhotoWorkerProvider.notifier);
    // Once, after the first frame: not on every rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepareInBackground());
    });
  }

  @override
  void dispose() {
    if (_startedRun) _worker.stop();
    super.dispose();
  }

  /// Starts the preparation of the photos that have no small copy yet, when
  /// preparation is on and the cache is below its limit. Already prepared and
  /// not convertible photos are skipped by the worker.
  Future<void> _prepareInBackground() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      if (!mounted || !settings.preparationEnabled) return;
      final sources = await ref.read(sourcesProvider.future);
      ref.invalidate(smallPhotoCacheUsageProvider);
      final usage = await ref.read(smallPhotoCacheUsageProvider.future);
      if (!mounted || usage.totalBytes >= settings.cacheLimitBytes) return;
      final snapshot = await ref.read(photoIndexStoreProvider).load();
      if (!mounted) return;
      final cache = ref.read(smallPhotoCacheProvider);
      final disabled = settings.disabledSourceIds.toSet();
      final sourcesById = {
        for (final s in sources)
          if (!disabled.contains(s.id)) s.id: s,
      };
      final pending = <PhotoItem>[];
      for (final item in snapshot.items) {
        if (!sourcesById.containsKey(item.sourceId)) continue;
        if (await cache.existing(item) == null) pending.add(item);
      }
      if (!mounted || pending.isEmpty) return;
      // Only a run that is not going yet is owned by this screen. A run of the
      // background jobs is joined, but not stopped on dispose.
      _startedRun = !ref.read(smallPhotoWorkerProvider).running;
      await _worker.start(pending, sourcesById);
    } catch (e, st) {
      logRecoverableError(
        'Preparation on the home screen could not start',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider).value ?? const <PhotoSource>[];
    final disabled = ref.watch(settingsProvider).value?.disabledSourceIds ??
        const <String>[];
    final index = ref.watch(_homeIndexProvider);
    final background = ref.watch(_backgroundPhotoProvider);
    final worker = ref.watch(smallPhotoWorkerProvider);
    final prepared = ref.watch(_preparedCountProvider);

    final enabledCount = sources.where((s) => !disabled.contains(s.id)).length;
    final snapshot = index.value;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Background(file: background.value),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text('PhotoFrame',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w300)),
                const SizedBox(height: 4),
                Text(
                  sources.isEmpty
                      ? 'Noch keine Quelle eingerichtet'
                      : '$enabledCount von ${sources.length} Quellen aktiv',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                _StatusCard(children: [
                  _StatusRow(
                    icon: Icons.photo_library_outlined,
                    label: 'Fotos im Index',
                    value: snapshot == null ? '…' : '${snapshot.items.length}',
                  ),
                  _StatusRow(
                    icon: Icons.update,
                    label: 'Index-Stand',
                    value: snapshot == null || snapshot.items.isEmpty
                        ? 'noch nicht aufgebaut'
                        : _stamp(snapshot.savedAt),
                  ),
                  _StatusRow(
                    icon: Icons.photo_size_select_small_outlined,
                    label: 'Verkleinert',
                    // Counted from the files on disk, so the number survives an app
                    // update or restart.
                    value: snapshot == null
                        ? '…'
                        : prepared.value == null
                            ? '…'
                            : '${prepared.value} von ${snapshot.items.length}'
                                '${worker.running ? ' (läuft, ${worker.waiting} wartend)' : ''}',
                  ),
                  _StatusRow(
                    icon: Icons.cloud_done_outlined,
                    label: 'Quellen',
                    value: sources.isEmpty
                        ? '–'
                        : sources.map((s) => s.type.name).toSet().join(', '),
                  ),
                ]),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.goNamed('slideshow'),
                  icon: const Icon(Icons.slideshow_outlined),
                  label: const Text('Diashow starten'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.photo_library_outlined,
                        label: 'Übersicht',
                        onTap: () => context.pushNamed('overview'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.settings_outlined,
                        label: 'Einstellungen',
                        onTap: () => context.pushNamed('settings'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'In der Diashow erreichst du diese Seite über das Haus-Symbol.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}. ${two(t.hour)}:${two(t.minute)}';
  }
}

/// The saved index, read once per visit to the start screen.
final FutureProvider<IndexSnapshot> _homeIndexProvider =
    FutureProvider.autoDispose<IndexSnapshot>(
  (ref) => ref.watch(photoIndexStoreProvider).load(),
);

/// How many photos of the index have a screen-sized copy on disk.
final FutureProvider<int> _preparedCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final snapshot = await ref.watch(_homeIndexProvider.future);
  final cache = ref.read(smallPhotoCacheProvider);
  var count = 0;
  for (final item in snapshot.items) {
    if (await cache.existing(item) != null) count++;
  }
  return count;
});

/// A random prepared photo as the background (null if none is ready yet).
final FutureProvider<File?> _backgroundPhotoProvider =
    FutureProvider.autoDispose<File?>((ref) async {
  final snapshot = await ref.watch(_homeIndexProvider.future);
  if (snapshot.items.isEmpty) return null;
  final cache = ref.read(smallPhotoCacheProvider);
  final random = math.Random();
  for (var attempt = 0; attempt < 8; attempt++) {
    final item = snapshot.items[random.nextInt(snapshot.items.length)];
    final file = await cache.verifiedExisting(item);
    if (file != null) return file;
  }
  return null;
});

class _Background extends StatelessWidget {
  const _Background({required this.file});

  final File? file;

  @override
  Widget build(BuildContext context) {
    const gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B3C7A), Color(0xFF14A89D)],
        ),
      ),
    );
    final photo = file;
    if (photo == null) return gradient;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(photo, fit: BoxFit.cover, cacheWidth: 800),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white.withValues(alpha: 0.12),
          child: Column(children: children),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        minimumSize: const Size.fromHeight(56),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Icon(icon), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}
