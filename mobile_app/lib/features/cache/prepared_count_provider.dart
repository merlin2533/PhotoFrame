import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../index/photo_index_store.dart';
import 'small_photo_cache.dart';

/// The saved photo index, read once per use. Shared by the start screen and
/// the preparing view.
final FutureProvider<IndexSnapshot> indexSnapshotProvider =
    FutureProvider.autoDispose<IndexSnapshot>(
  (ref) => ref.watch(photoIndexStoreProvider).load(),
);

/// How many photos of the index have a screen-sized copy on disk, counted with
/// [SmallPhotoCache.existingFileNames]. Invalidate it when the cache changed, e.g. after
/// every photo the worker finished.
final FutureProvider<int> preparedCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final snapshot = await ref.watch(indexSnapshotProvider.future);
  final cache = ref.read(smallPhotoCacheProvider);
  final names = await cache.existingFileNames();
  return snapshot.items
      .where((i) => names.contains(SmallPhotoCache.fileNameFor(i)))
      .length;
});
