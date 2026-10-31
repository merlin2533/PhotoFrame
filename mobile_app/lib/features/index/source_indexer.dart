import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sources/domain/photo_folder.dart';
import '../sources/domain/photo_item.dart';
import '../sources/domain/photo_source.dart';
import '../sources/state/source_stats.dart';
import 'photo_index_store.dart';

/// Where the index build for one source stands.
class SourceIndexStatus {
  const SourceIndexStatus({
    required this.running,
    required this.imageCount,
    this.error,
  });

  final bool running;
  final int imageCount;
  final String? error;
}

/// Builds the photo index of a single source on demand ("Index jetzt
/// aufbauen" in the sources list). Runs in the background, reports progress
/// per source, and replaces only that source's photos in the saved index.
class SourceIndexer extends Notifier<Map<String, SourceIndexStatus>> {
  @override
  Map<String, SourceIndexStatus> build() => const {};

  Future<void> buildIndex(PhotoSource source) async {
    if (state[source.id]?.running ?? false) return;
    void report(int count, {String? error, bool running = true}) {
      state = {
        ...state,
        source.id: SourceIndexStatus(
          running: running,
          imageCount: count,
          error: error,
        ),
      };
    }

    report(0);
    try {
      final items = await crawlSource(source, onProgress: (n) => report(n));
      final store = ref.read(photoIndexStoreProvider);
      // Replace only this source's photos (serialized with other index jobs).
      await store.merge(items, replacing: {source.id});
      ref.read(sourceStatsProvider.notifier).record(source.id, items.length);
      report(items.length, running: false);
    } catch (e) {
      report(state[source.id]?.imageCount ?? 0, error: '$e', running: false);
    }
  }
}

final NotifierProvider<SourceIndexer, Map<String, SourceIndexStatus>>
    sourceIndexerProvider =
    NotifierProvider<SourceIndexer, Map<String, SourceIndexStatus>>(
  SourceIndexer.new,
);

/// Crawls all folders of [source] (no time limit) and returns its photos.
Future<List<PhotoItem>> crawlSource(
  PhotoSource source, {
  void Function(int found)? onProgress,
}) async {
  final seen = <String, PhotoItem>{};
  void collect(PhotoItem item) {
    seen['${item.sourceId}::${item.id}'] = item;
    onProgress?.call(seen.length);
  }

  const root = PhotoFolder(id: '', name: '', path: '');
  await for (final r in source.listImages(root, recursive: false)) {
    final item = r.valueOrNull;
    if (item != null) collect(item);
  }
  final folders = <PhotoFolder>[];
  await for (final f in source.listFolders()) {
    final folder = f.valueOrNull;
    if (folder != null) folders.add(folder);
  }
  for (final folder in folders) {
    await for (final r in source.listImages(folder)) {
      final item = r.valueOrNull;
      if (item != null) collect(item);
    }
  }
  return seen.values.toList(growable: false);
}
