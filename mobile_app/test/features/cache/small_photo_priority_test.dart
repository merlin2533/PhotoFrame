import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/cancellation_token.dart';
import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/cache/slideshow_busy.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';

/// Cache whose scaling step only records when it starts. The real scaler
/// needs the native plugin, which is not available in unit tests.
class _RecordingCache extends SmallPhotoCache {
  _RecordingCache(Directory dir) : super(directory: () async => dir);

  final List<DateTime> scaleStarts = [];

  @override
  Future<File?> scaleCopy(File full, File temp) async {
    scaleStarts.add(DateTime.now());
    await temp.writeAsBytes([1, 2, 3]);
    return temp;
  }
}

/// Hands out a small complete file for every photo, so the download step
/// succeeds without a network.
class _DownloadSource extends MockPhotoSource {
  _DownloadSource(this.dir)
      : super(
          id: 'dl',
          folderCount: 1,
          itemsPerFolder: 0,
          simulatedDelay: Duration.zero,
        );

  final Directory dir;

  @override
  Future<Result<File>> fetchToCache(
    PhotoItem item, {
    CancellationToken? token,
  }) async {
    final file = File('${dir.path}/${item.id}.download');
    await file.writeAsBytes([1, 2, 3]);
    return Result.ok(file);
  }
}

class _FixedSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

PhotoItem _item(String id) => PhotoItem(
      id: id,
      sourceId: 'dl',
      folderId: 'folder',
      name: '$id.jpg',
      mediaType: MediaType.image,
      size: 3,
      mtime: DateTime(2024),
    );

ProviderContainer _container(SmallPhotoCache cache) {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scaling does not start while the slideshow is busy', () async {
    final dir = await Directory.systemTemp.createTemp('priority_test_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final cache = _RecordingCache(dir);
    final container = _container(cache);
    final busy = container.read(slideshowBusyProvider);
    final worker = container.read(smallPhotoWorkerProvider.notifier);
    final source = _DownloadSource(dir);

    busy.busy = true;
    final run = worker.start([_item('a')], {source.id: source});

    // Well past the poll interval: the download may finish, scaling must not.
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(cache.scaleStarts, isEmpty);
    expect(container.read(smallPhotoWorkerProvider).done, 0);

    busy.busy = false;
    await run;

    expect(cache.scaleStarts, hasLength(1));
    expect(container.read(smallPhotoWorkerProvider).done, 1);
  });

  test('the wait for an idle slideshow ends after 30 seconds', () {
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: [
          smallPhotoCacheProvider.overrideWithValue(
            SmallPhotoCache(directory: () async => Directory.systemTemp),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(slideshowBusyProvider).busy = true;
      final worker = container.read(smallPhotoWorkerProvider.notifier);

      var finished = false;
      worker.waitForSlideshowForTest().then((_) => finished = true);

      async.elapse(const Duration(seconds: 29));
      expect(finished, isFalse, reason: 'still waiting before the 30 s cap');

      async.elapse(const Duration(seconds: 2));
      expect(finished, isTrue, reason: 'proceeds after the 30 s cap');
    });
  });

  test('the wait returns at once when the slideshow is idle', () {
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: [
          smallPhotoCacheProvider.overrideWithValue(
            SmallPhotoCache(directory: () async => Directory.systemTemp),
          ),
        ],
      );
      addTearDown(container.dispose);
      final worker = container.read(smallPhotoWorkerProvider.notifier);

      var finished = false;
      worker.waitForSlideshowForTest().then((_) => finished = true);
      async.flushMicrotasks();
      expect(finished, isTrue);
    });
  });
}
