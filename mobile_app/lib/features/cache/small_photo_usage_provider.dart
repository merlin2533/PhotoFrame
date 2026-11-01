import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sources/state/sources_providers.dart';
import 'small_photo_cache.dart';

/// Count and size of the small-photo cache, per configured source. Scans the
/// cache folder, so it is invalidated after the cache was changed (see the
/// cache settings screen).
final FutureProvider<SmallPhotoCacheUsage> smallPhotoCacheUsageProvider =
    FutureProvider<SmallPhotoCacheUsage>((ref) async {
  final sources = await ref.watch(sourcesProvider.future);
  return ref
      .read(smallPhotoCacheProvider)
      .usage(sources.map((source) => source.id));
});
