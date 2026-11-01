import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/cache/small_photo_usage_provider.dart';
import 'package:mobile_app/features/index/photo_index_store.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/state/sources_providers.dart';
import 'package:mobile_app/screens/home_screen.dart';

/// Usage of a cache with [count] photos on disk.
SmallPhotoCacheUsage _usage(int count) => SmallPhotoCacheUsage(
      bySource: const [],
      unassignedCount: count,
      unassignedBytes: 0,
    );

class _NoSourcesController extends SourcesController {
  @override
  Future<List<PhotoSource>> build() async => const [];
}

/// Preparation off: the start screen does not start the worker in this test.
class _PreparationOffSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(smallPhotoPreparation: false);
}

/// Stand-in worker that never prepares anything. [finishOne] reports one more
/// finished photo, as a running worker does after each photo.
class _FakeWorker extends SmallPhotoWorker {
  void finishOne() => state = SmallPhotoStatus(done: state.done + 1);
}

void main() {
  testWidgets('shows the number of downloaded photos and updates it live',
      (tester) async {
    var cachedPhotos = 7;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sourcesProvider.overrideWith(_NoSourcesController.new),
        settingsProvider.overrideWith(_PreparationOffSettings.new),
        photoIndexStoreProvider.overrideWithValue(
          PhotoIndexStore(read: () async => null, write: (_) async {}),
        ),
        smallPhotoCacheUsageProvider
            .overrideWith((ref) async => _usage(cachedPhotos)),
        smallPhotoWorkerProvider.overrideWith(_FakeWorker.new),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Heruntergeladen'), findsOneWidget);
    expect(find.text('7 Fotos'), findsOneWidget);

    // One more photo is downloaded and prepared: the counter follows without
    // leaving the screen.
    cachedPhotos = 8;
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    (container.read(smallPhotoWorkerProvider.notifier) as _FakeWorker)
        .finishOne();
    await tester.pumpAndSettle();

    expect(find.text('8 Fotos'), findsOneWidget);
    expect(find.text('7 Fotos'), findsNothing);
  });

  testWidgets('the cache count is read again when the app resumes',
      (tester) async {
    var cachedPhotos = 3;
    var reads = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sourcesProvider.overrideWith(_NoSourcesController.new),
        settingsProvider.overrideWith(_PreparationOffSettings.new),
        photoIndexStoreProvider.overrideWithValue(
          PhotoIndexStore(read: () async => null, write: (_) async {}),
        ),
        smallPhotoCacheUsageProvider.overrideWith((ref) async {
          reads++;
          return _usage(cachedPhotos);
        }),
        smallPhotoWorkerProvider.overrideWith(_FakeWorker.new),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('3 Fotos'), findsOneWidget);
    final readsBefore = reads;

    // Photos were removed while the app was in the background.
    cachedPhotos = 1;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(reads, greaterThan(readsBefore));
    expect(find.text('1 Fotos'), findsOneWidget);
    expect(find.text('3 Fotos'), findsNothing);
  });
}
