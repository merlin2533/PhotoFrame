import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cache/small_photo_cache.dart';
import '../../index/photo_index_store.dart';
import '../../sources/domain/photo_item.dart';
import '../../sources/domain/photo_source.dart';
import '../../sources/local/local_folder_source.dart';
import '../../sources/state/source_stats.dart';
import '../../sources/state/sources_providers.dart';

/// Lists the connected sources and every photo in the saved index as a grid.
/// Tap a photo to see it larger.
class PhotoOverviewScreen extends ConsumerWidget {
  const PhotoOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? const <PhotoSource>[];
    final stats = ref.watch(sourceStatsProvider);
    final index = ref.watch(_indexProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Übersicht')),
      body: index.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Index konnte nicht gelesen werden:\n$e',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(_indexProvider),
                child: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
        data: (items) {
          final byId = {for (final s in sources) s.id: s};
          return Column(
            children: [
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final s in sources)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.displayName,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(
                                '${items.where((i) => i.sourceId == s.id).length} Bilder',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (stats[s.id] != null)
                                Text(
                                  'Stand ${_stamp(stats[s.id]!.updatedAt)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Noch keine Bilder im Index.'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(4),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 120,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final source = byId[item.sourceId];
                          return GestureDetector(
                            onTap: source == null
                                ? null
                                : () => _showLarger(context, source, item),
                            child: _Thumb(item: item, source: source),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}. ${two(t.hour)}:${two(t.minute)}';
  }

  static void _showLarger(
      BuildContext context, PhotoSource source, PhotoItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: _Large(source: source, item: item)),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton.filled(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: Text(
                  '${source.displayName} › ${item.id}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reads the saved index once per visit.
final FutureProvider<List<PhotoItem>> _indexProvider =
    FutureProvider<List<PhotoItem>>((ref) async {
  final snapshot = await ref.watch(photoIndexStoreProvider).load();
  return snapshot.items;
});

/// Local file of a photo, if its source keeps it on this device.
File? _localFile(PhotoSource? source, PhotoItem item) {
  if (source is! LocalFolderSource) return null;
  final root = source.rootPath;
  if (root == null) return null;
  return File('$root${Platform.pathSeparator}${item.id}');
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.item, required this.source});

  final PhotoItem item;
  final PhotoSource? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = _localFile(source, item);
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 240,
        errorBuilder: (_, __, ___) => _Placeholder(name: item.name),
      );
    }
    // Network photos: show the prepared small file once it exists.
    return FutureBuilder<File?>(
      future: ref.read(smallPhotoCacheProvider).existing(item),
      builder: (context, snapshot) {
        final small = snapshot.data;
        if (small != null) {
          return Image.file(
            small,
            fit: BoxFit.cover,
            cacheWidth: 240,
            errorBuilder: (_, __, ___) => _Placeholder(name: item.name),
          );
        }
        // Not prepared yet: show the photo itself, downloaded on demand.
        final source = this.source;
        if (source == null) return _Placeholder(name: item.name);
        return FutureBuilder<File?>(
          future: _OneAtATime.run(() => source.fetchToCache(item))
              .then((r) => r.valueOrNull)
              .catchError((_) => null),
          builder: (context, original) {
            final file = original.data;
            if (file == null) return _Placeholder(name: item.name);
            return Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth: 240,
              errorBuilder: (_, __, ___) => _Placeholder(name: item.name),
            );
          },
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final hue = (name.hashCode % 360).abs().toDouble();
    return ColoredBox(
      color: HSVColor.fromAHSV(1, hue, 0.45, 0.55).toColor(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
    );
  }
}

/// Full-size view. Local photos are shown directly; network photos are
/// downloaded first (same cache as the slideshow).
class _Large extends StatelessWidget {
  const _Large({required this.source, required this.item});

  final PhotoSource source;
  final PhotoItem item;

  @override
  Widget build(BuildContext context) {
    final local = _localFile(source, item);
    if (local != null) {
      return InteractiveViewer(child: Image.file(local));
    }
    return FutureBuilder<File?>(
      future: source
          .fetchToCache(item)
          .then((r) => r.valueOrNull)
          .catchError((_) => null),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const CircularProgressIndicator();
        }
        final file = snapshot.data;
        if (file == null) {
          return const Text('Foto konnte nicht geladen werden',
              style: TextStyle(color: Colors.white));
        }
        return InteractiveViewer(child: Image.file(file));
      },
    );
  }
}

/// Runs downloads one after the other, so scrolling the overview does not
/// start many network transfers at once.
class _OneAtATime {
  static Future<void> _tail = Future.value();

  static Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
