import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';

/// Records every item it is asked to prepare. Items in [failing] report that
/// they could not be read.
class _FakeCache extends SmallPhotoCache {
  _FakeCache({this.failing = const <String>{}})
      : super(directory: () async => Directory.systemTemp);

  final Set<String> failing;
  final List<String> calls = [];
  final List<DateTime> callTimes = [];

  @override
  Future<File?> ensure(
    PhotoSource source,
    PhotoItem item, {
    Future<void> Function()? beforeScale,
  }) async {
    calls.add(item.id);
    callTimes.add(DateTime.now());
    return failing.contains(item.id) ? null : File('${item.id}.jpg');
  }
}

class _FixedSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

PhotoItem _item(String id) => PhotoItem(
      id: id,
      sourceId: 'src',
      folderId: 'folder',
      name: '$id.jpg',
      mediaType: MediaType.image,
      size: 1,
      mtime: DateTime(2024),
    );

ProviderContainer _container(_FakeCache cache) {
  final container = ProviderContainer(
    overrides: [
      smallPhotoCacheProvider.overrideWithValue(cache),
      settingsProvider.overrideWith(_FixedSettings.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('an item already prepared is not queued or counted again', () async {
    final cache = _FakeCache();
    final container = _container(cache);
    final worker = container.read(smallPhotoWorkerProvider.notifier);
    final source =
        MockPhotoSource(id: 'src', folderCount: 1, itemsPerFolder: 0);
    final a = _item('a');
    final b = _item('b');

    await worker.start([a], {source.id: source});
    await worker.start([a, b], {source.id: source});
    await worker.prioritize(a, source);

    expect(cache.calls, ['a', 'b']);
    final status = container.read(smallPhotoWorkerProvider);
    expect(status.total, 2);
    expect(status.done, 2);
  });

  test('the worker pauses between two items, not only between batches',
      () async {
    final cache = _FakeCache();
    final container = _container(cache);
    final worker = container.read(smallPhotoWorkerProvider.notifier);
    final source =
        MockPhotoSource(id: 'src', folderCount: 1, itemsPerFolder: 0);

    await worker.start(
      [_item('a'), _item('b'), _item('c')],
      {source.id: source},
    );

    expect(cache.calls, hasLength(3));
    // Tolerance for timer rounding; the pause itself is 1500 ms.
    const tolerance = Duration(milliseconds: 20);
    for (var i = 1; i < cache.callTimes.length; i++) {
      final gap = cache.callTimes[i].difference(cache.callTimes[i - 1]);
      expect(
        gap,
        greaterThanOrEqualTo(SmallPhotoWorker.itemPause - tolerance),
        reason: 'pause before item ${i + 1}',
      );
    }
  });

  test('a failed photo is not retried within the hour', () async {
    final cache = _FakeCache(failing: {'bad'});
    final container = _container(cache);
    final worker = container.read(smallPhotoWorkerProvider.notifier);
    final source =
        MockPhotoSource(id: 'src', folderCount: 1, itemsPerFolder: 0);
    final bad = _item('bad');

    await worker.start([bad], {source.id: source});
    await worker.start([bad], {source.id: source});
    await worker.prioritize(bad, source);

    expect(cache.calls, ['bad']);
    final status = container.read(smallPhotoWorkerProvider);
    expect(status.total, 1);
    expect(status.done, 1);
  });
}
