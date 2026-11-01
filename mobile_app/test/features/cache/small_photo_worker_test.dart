import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/not_convertible_store.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every item it is asked to prepare. Items in [failing] report that
/// they could not be read.
class _FakeCache extends SmallPhotoCache {
  _FakeCache({
    this.failing = const <String>{},
    this.notScalable = const <String>{},
    this.throwing = const <String>{},
  }) : super(directory: () async => Directory.systemTemp);

  /// Download fails: ensure returns null.
  final Set<String> failing;

  /// Refused by the scaler: ensure throws [PhotoNotConvertibleException].
  final Set<String> notScalable;

  /// The scaling step throws: ensure throws a plain error wrapped by the cache.
  final Set<String> throwing;
  final List<String> calls = [];

  @override
  Future<File?> ensure(PhotoSource source, PhotoItem item) async {
    calls.add(item.id);
    if (notScalable.contains(item.id)) {
      throw const PhotoNotConvertibleException(
          'Format is neither JPEG nor PNG');
    }
    if (throwing.contains(item.id)) {
      throw PhotoNotConvertibleException(
        'Scaling threw an exception',
        cause: StateError('scaler broke'),
      );
    }
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('a photo whose scaling fails is marked and never scaled again',
      () async {
    final cache = _FakeCache(throwing: {'broken'});
    final container = _container(cache);
    final worker = container.read(smallPhotoWorkerProvider.notifier);
    final source =
        MockPhotoSource(id: 'src', folderCount: 1, itemsPerFolder: 0);
    final broken = _item('broken');

    await worker.start([broken], {source.id: source});
    await worker.start([broken], {source.id: source});
    await worker.prioritize(broken, source);

    expect(cache.calls, ['broken']);
    expect(
        await container.read(notConvertibleStoreProvider).contains(
              broken.stableId,
            ),
        isTrue);
    final status = container.read(smallPhotoWorkerProvider);
    expect(status.done, 1);
    expect(status.running, isFalse);
  });

  test('a photo refused by the scaler is marked and the worker goes on',
      () async {
    final cache = _FakeCache(notScalable: {'heic'});
    final container = _container(cache);
    final worker = container.read(smallPhotoWorkerProvider.notifier);
    final source =
        MockPhotoSource(id: 'src', folderCount: 1, itemsPerFolder: 0);
    final heic = _item('heic');
    final next = _item('next');

    await worker.start([heic, next], {source.id: source});

    expect(cache.calls.toSet(), {'heic', 'next'});
    final store = container.read(notConvertibleStoreProvider);
    expect(await store.contains(heic.stableId), isTrue);
    expect(await store.contains(next.stableId), isFalse);
  });

  test('a marked photo is skipped by later runs', () async {
    final cache = _FakeCache(notScalable: {'heic'});
    final container = _container(cache);
    final worker = container.read(smallPhotoWorkerProvider.notifier);
    final source =
        MockPhotoSource(id: 'src', folderCount: 1, itemsPerFolder: 0);
    final heic = _item('heic');

    await worker.start([heic], {source.id: source});
    await worker.start([heic], {source.id: source});

    expect(cache.calls, ['heic']);
  });
}
