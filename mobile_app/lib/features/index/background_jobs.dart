import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';
import '../cache/small_photo_cache.dart';
import '../settings/domain/app_settings.dart';
import '../settings/state/settings_providers.dart';
import '../sources/domain/photo_item.dart';
import '../sources/domain/photo_source.dart';
import '../sources/state/sources_providers.dart';
import 'photo_index_store.dart';
import 'source_indexer.dart';

/// Keeps the photo index, the cache and the screen-sized copies up to date
/// without the slideshow having to run:
///
/// 1. When the saved index is older than `indexRefreshHours`, every enabled
///    source is crawled again and the index is replaced source by source.
/// 2. Every photo of the index gets its screen-sized copy (in batches, see
///    [SmallPhotoWorker]).
///
/// Runs once at start and then every [interval]. Runs never overlap.
class BackgroundJobs extends Notifier<bool> {
  static const interval = Duration(minutes: 15);

  Timer? _timer;
  bool _running = false;

  /// Whether a run is in progress right now.
  @override
  bool build() {
    _timer = Timer.periodic(interval, (_) => unawaited(runOnce()));
    ref.onDispose(() => _timer?.cancel());
    // Deferred: runOnce sets `state`, which is not allowed inside build().
    unawaited(Future<void>.delayed(Duration.zero, runOnce));
    return false;
  }

  Future<void> runOnce() async {
    if (_running) return;
    _running = true;
    state = true;
    try {
      final settings = ref.read(settingsProvider).value;
      if (settings == null) return;
      final sources = await ref.read(sourcesProvider.future);
      final enabled = sources
          .where((s) => !settings.disabledSourceIds.contains(s.id))
          .toList();
      final store = ref.read(photoIndexStoreProvider);
      var snapshot = await store.load();
      // Preparation of the photos we already know starts right away and runs
      // alongside the index refresh; new photos are queued into the same run.
      unawaited(_prepareSmallPhotos(_enabledItems(snapshot, enabled), enabled));
      final due = snapshot.items.isEmpty ||
          snapshot.age(DateTime.now()) >=
              Duration(hours: settings.indexRefreshHours);
      if (due) {
        for (final source in enabled) {
          snapshot = await _refreshSource(source, store, snapshot);
        }
        unawaited(
            _prepareSmallPhotos(_enabledItems(snapshot, enabled), enabled));
      }
    } catch (e, st) {
      // Next run tries again.
      logRecoverableError('Background index run failed',
          error: e, stackTrace: st);
    } finally {
      _running = false;
      state = false;
    }
  }

  List<PhotoItem> _enabledItems(
      IndexSnapshot snapshot, List<PhotoSource> enabled) {
    // Built once: a per-item scan over `enabled` is O(items * sources).
    final enabledIds = {for (final s in enabled) s.id};
    return snapshot.items
        .where((i) => enabledIds.contains(i.sourceId))
        .toList();
  }

  /// Replaces the photos of one source in the saved index. Returns the index
  /// after the replacement, or [current] when the crawl failed.
  Future<IndexSnapshot> _refreshSource(
    PhotoSource source,
    PhotoIndexStore store,
    IndexSnapshot current,
  ) async {
    try {
      final items = await crawlSource(source);
      return await store.merge(items, replacing: {source.id});
    } catch (e, st) {
      // A failing source keeps its saved photos; the other sources still run.
      logRecoverableError('Crawl of source ${source.id} failed',
          error: e, stackTrace: st);
      return current;
    }
  }

  Future<void> _prepareSmallPhotos(
    List<PhotoItem> items,
    List<PhotoSource> sources,
  ) async {
    // Single gate for all background preparation (both calls in runOnce).
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    if (!settings.preparationEnabled) return;
    // Random order: the copies that exist are a random sample of the library.
    await ref.read(smallPhotoWorkerProvider.notifier).start(
      List<PhotoItem>.of(items)..shuffle(),
      {for (final s in sources) s.id: s},
    );
  }
}

final NotifierProvider<BackgroundJobs, bool> backgroundJobsProvider =
    NotifierProvider<BackgroundJobs, bool>(BackgroundJobs.new);
