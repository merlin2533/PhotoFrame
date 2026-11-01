import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/cancellation_token.dart';
import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/index/background_jobs.dart';
import 'package:mobile_app/features/index/photo_index_store.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/features/sources/domain/photo_folder.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:mobile_app/features/sources/state/sources_providers.dart';

/// Settings fixed to the defaults, so the job does not read shared preferences.
class _FixedSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

/// Settings fixed to [settings], so the job reads them without preferences.
class _FixedSettingsWith extends AppSettingsController {
  _FixedSettingsWith(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

/// Sources fixed to a caller-supplied list.
class _FixedSources extends SourcesController {
  _FixedSources(this._initial);

  final List<PhotoSource> _initial;

  @override
  Future<List<PhotoSource>> build() async => _initial;
}

/// Records which photos the job hands over for preparation, without touching
/// the file system.
class _RecordingWorker extends SmallPhotoWorker {
  _RecordingWorker(this.started);

  final List<List<PhotoItem>> started;

  @override
  Future<void> start(
    List<PhotoItem> items,
    Map<String, PhotoSource> sourcesById,
  ) async {
    started.add(items);
  }
}

/// A source whose folder listing always fails, like an unreachable share.
class _BrokenSource extends MockPhotoSource {
  _BrokenSource() : super(id: 'broken', simulatedDelay: Duration.zero);

  @override
  Stream<Result<PhotoFolder>> listFolders({
    PhotoFolder? parent,
    CancellationToken? token,
  }) =>
      Stream.error(StateError('share unreachable'));
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('the index is still refreshed but no preparation runs when it is off',
      () async {
    final good = MockPhotoSource(
      id: 'good',
      simulatedDelay: Duration.zero,
      folderCount: 1,
      itemsPerFolder: 3,
    );
    addTearDown(good.dispose);

    String? stored;
    final store = PhotoIndexStore(
      read: () async => stored,
      write: (json) async => stored = json,
    );
    final started = <List<PhotoItem>>[];
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _FixedSettingsWith(
            const AppSettings().copyWith(smallPhotoPreparation: false),
          )),
      sourcesProvider.overrideWith(() => _FixedSources([good])),
      photoIndexStoreProvider.overrideWithValue(store),
      smallPhotoWorkerProvider.overrideWith(() => _RecordingWorker(started)),
    ]);
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    container.read(backgroundJobsProvider);
    // Wait until the run has saved the index and has finished.
    await _waitUntil(() =>
        container.read(backgroundJobsProvider) == false && stored != null);

    final saved = await store.load();
    expect(saved.items, isNotEmpty);
    expect(started, isEmpty);
  });

  test('a failing source keeps the others and only the working one is indexed',
      () async {
    final good = MockPhotoSource(
      id: 'good',
      simulatedDelay: Duration.zero,
      folderCount: 1,
      itemsPerFolder: 3,
    );
    final broken = _BrokenSource();
    addTearDown(good.dispose);
    addTearDown(broken.dispose);

    String? stored;
    final store = PhotoIndexStore(
      read: () async => stored,
      write: (json) async => stored = json,
    );
    final started = <List<PhotoItem>>[];
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_FixedSettings.new),
      sourcesProvider.overrideWith(() => _FixedSources([good, broken])),
      photoIndexStoreProvider.overrideWithValue(store),
      smallPhotoWorkerProvider.overrideWith(() => _RecordingWorker(started)),
    ]);
    addTearDown(container.dispose);

    // The job skips a run while the settings are still loading, so wait for
    // them first. Reading the provider then starts the job.
    await container.read(settingsProvider.future);
    container.read(backgroundJobsProvider);
    await _waitUntil(() => started.any((list) => list.isNotEmpty));

    final saved = await store.load();
    expect(saved.items, isNotEmpty);
    expect(saved.items.every((i) => i.sourceId == 'good'), isTrue);
    final prepared = started.lastWhere((list) => list.isNotEmpty);
    expect(prepared.every((i) => i.sourceId == 'good'), isTrue);
  });
}
