import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/small_photo_cache.dart';
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
      final due = snapshot.items.isEmpty ||
          snapshot.age(DateTime.now()) >=
              Duration(hours: settings.indexRefreshHours);
      if (due) {
        for (final source in enabled) {
          await _refreshSource(source, store);
        }
        snapshot = await store.load();
      }
      final items = snapshot.items
          .where((i) => enabled.any((s) => s.id == i.sourceId))
          .toList();
      await _prepareSmallPhotos(items, enabled);
    } catch (_) {
      // Next run tries again; nothing else to do here.
    } finally {
      _running = false;
      state = false;
    }
  }

  /// Replaces the photos of one source in the saved index.
  Future<void> _refreshSource(PhotoSource source, PhotoIndexStore store) async {
    try {
      final items = await crawlSource(source);
      await store.merge(items, replacing: {source.id});
    } catch (_) {
      // A failing source keeps its saved photos.
    }
  }

  Future<void> _prepareSmallPhotos(
    List<PhotoItem> items,
    List<PhotoSource> sources,
  ) async {
    // Random order: the copies that exist are a random sample of the library.
    await ref.read(smallPhotoWorkerProvider.notifier).start(
      List<PhotoItem>.of(items)..shuffle(),
      {for (final s in sources) s.id: s},
    );
  }
}

final NotifierProvider<BackgroundJobs, bool> backgroundJobsProvider =
    NotifierProvider<BackgroundJobs, bool>(BackgroundJobs.new);
