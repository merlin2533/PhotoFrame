import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/index/working_set_pool.dart';
import 'package:mobile_app/features/slideshow/domain/slideshow_config.dart';
import 'package:mobile_app/features/slideshow/domain/slideshow_engine.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';

void main() {
  test('showPrevious goes back to the photo shown before', () async {
    final items = {
      for (var i = 0; i < 5; i++)
        'p$i': PhotoItem(
          id: 'p$i',
          sourceId: 's',
          folderId: '',
          name: 'p$i',
          mediaType: MediaType.image,
          size: 1,
          mtime: DateTime(2026),
        ),
    };
    final pool = InMemoryWorkingSetPool(targetSize: 10);
    for (final id in items.keys) {
      pool.add(
          PoolEntry(sourceId: 's', itemId: id, addedToPoolAt: DateTime(2026)));
    }
    final engine = SlideshowEngine(
      pool: pool,
      sources: const {},
      resolveItem: (entry) async => items[entry.itemId],
      config: const SlideshowConfig(interval: Duration(hours: 1)),
    );
    await engine.start();
    final first = engine.currentItem!;
    await engine.skipToNext();
    final second = engine.currentItem!;
    expect(second.id, isNot(first.id));

    await engine.showPrevious();
    expect(engine.currentItem!.id, first.id);

    // At the start of the history nothing happens.
    await engine.showPrevious();
    expect(engine.currentItem!.id, first.id);
    await engine.dispose();
  });
}
