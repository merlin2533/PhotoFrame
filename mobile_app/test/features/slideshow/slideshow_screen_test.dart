import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/errors/failure.dart';
import 'package:mobile_app/core/utils/cancellation_token.dart';
import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/index/photo_index_store.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/features/slideshow/domain/always_on_controller.dart';
import 'package:mobile_app/features/slideshow/presentation/slideshow_screen.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/empty_state_view.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/slide_renderer.dart';
import 'package:mobile_app/features/slideshow/state/slideshow_providers.dart';
import 'package:mobile_app/features/sources/domain/photo_folder.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:mobile_app/features/sources/state/sources_providers.dart';
import 'package:mobile_app/services/kiosk/kiosk_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins the transition to fade (with the random default, zoom makes
/// pumpAndSettle time out) and allows raw downloads, because a MockPhotoSource
/// has no prepared small copy.
class _FixedSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings(
        transition: SlideshowTransition.fade,
        onlyPreparedPhotos: false,
      );
}

/// No-op [WakelockController] so widget tests never touch the real
/// `wakelock_plus` platform channel (which isn't registered under
/// `flutter test` and isn't the concern of this screen's tests anyway).
class _FakeWakelock implements WakelockController {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

/// No-op [KioskModeController] so widget tests never touch the real
/// "photoframe/kiosk" platform channel - see that class's doc comment for
/// why exercising the real channel needs an actual Android device.
class _FakeKioskModeController implements KioskModeController {
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

/// Fixes [sourcesProvider] to a caller-supplied list instead of the default
/// single-`MockPhotoSource` registry, without touching secure-storage
/// pruning (see `SourcesController.build`'s doc comment) - irrelevant noise
/// for these tests.
class _FixedSourcesController extends SourcesController {
  _FixedSourcesController(this._initial);

  final List<PhotoSource> _initial;

  @override
  Future<List<PhotoSource>> build() async => _initial;
}

Widget _wrap(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the empty state when no photo source is configured',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SlideshowScreen(),
        overrides: [
          sourcesProvider.overrideWith(() => _FixedSourcesController(const [])),
          alwaysOnControllerProvider.overrideWithValue(
            AlwaysOnController(wakelock: _FakeWakelock()),
          ),
          kioskModeControllerProvider
              .overrideWithValue(_FakeKioskModeController()),
          networkCacheCleanerProvider.overrideWithValue(() async {}),
          smallPhotoCacheProvider.overrideWithValue(_NoSmallPhotoCache()),
          smallPhotoWorkerProvider.overrideWith(_NoWorker.new),
          photoIndexStoreProvider.overrideWithValue(PhotoIndexStore(
            read: () async => null,
            write: (_) async {},
          )),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmptyStateView), findsOneWidget);
    expect(find.text('Noch keine Bilder'), findsOneWidget);
    expect(find.byType(SlideRenderer), findsNothing);

    // Tear the widget down explicitly so `SlideshowScreen.dispose()` runs
    // (it holds no engine/timers here, but this keeps the pattern identical
    // to the populated-source test below).
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('renders the current item once a MockPhotoSource is registered',
      (tester) async {
    final source = MockPhotoSource(
      id: 'mock-1',
      folderCount: 1,
      itemsPerFolder: 3,
      simulatedDelay: Duration.zero,
    );
    final kiosk = _FakeKioskModeController();

    // Kept alive across the whole test (not swapped out with the screen
    // below) so the ProviderScope's container isn't torn down in the same
    // pass as `SlideshowScreen` itself - mirrors what actually happens when
    // `go_router` navigates away from `/slideshow` in the real app (the
    // ProviderScope stays mounted at the app root; only the screen widget
    // is removed).
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourcesProvider.overrideWith(() => _FixedSourcesController([source])),
          settingsProvider.overrideWith(_FixedSettings.new),
          alwaysOnControllerProvider.overrideWithValue(
            AlwaysOnController(wakelock: _FakeWakelock()),
          ),
          kioskModeControllerProvider.overrideWithValue(kiosk),
          networkCacheCleanerProvider.overrideWithValue(() async {}),
          smallPhotoCacheProvider.overrideWithValue(_NoSmallPhotoCache()),
          smallPhotoWorkerProvider.overrideWith(_NoWorker.new),
          photoIndexStoreProvider.overrideWithValue(PhotoIndexStore(
            read: () async => null,
            write: (_) async {},
          )),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, isVisible, _) =>
                isVisible ? const SlideshowScreen() : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmptyStateView), findsNothing);
    expect(find.byType(SlideRenderer), findsOneWidget);
    // SlideRenderer's placeholder (see its doc comment on why it can't
    // decode MockPhotoSource's non-image bytes) still renders the item's
    // real name, so this confirms the *actual* resolved PhotoItem reached
    // the renderer, not just "some" SlideRenderer instance.
    expect(find.textContaining('mock_0_'), findsWidgets);

    // kioskModeEnabled defaults to false (see AppSettings), so entering the
    // slideshow must not have engaged kiosk/screen-pinning.
    expect(kiosk.startCalls, 0);

    // Remove the screen (simulating navigating away) and make sure it
    // releases its engine/timers cleanly - a leaked `Timer.periodic` would
    // otherwise fail this test at teardown ("A Timer is still pending").
    visible.value = false;
    await tester.pumpAndSettle();
    expect(kiosk.stopCalls, 1);
  });

  testWidgets('a photo without a prepared copy stays in the pool',
      (tester) async {
    final source = _OnceListedSource();
    addTearDown(source.dispose);
    await tester.pumpWidget(_screenWith(source, _PreparedOnlySettings.new));

    // Every photo is shown and skipped as "not prepared" several times over.
    // Before, that emptied the pool and the empty state replaced the slides.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(EmptyStateView), findsNothing);
    // During a fade two slides can be mounted at once, so only require that a
    // slide is shown, not exactly one.
    expect(find.byType(SlideRenderer), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an emptied pool shows the empty state without an error',
      (tester) async {
    final source = _OnceListedSource(unreadable: true);
    addTearDown(source.dispose);
    await tester.pumpWidget(_screenWith(source, _RawSettings.new));

    // Both photos cannot be read, so both are removed from the pool.
    for (var i = 0;
        i < 12 && find.byType(EmptyStateView).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(EmptyStateView), findsOneWidget);
    expect(find.byType(SlideRenderer), findsNothing);

    // The engine keeps ticking on the emptied pool without an exception
    // (ShuffleBag would throw on an empty list).
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(EmptyStateView), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('clearNetworkCache keeps a recently modified download', () async {
    final dir = await Directory.systemTemp.createTemp('cache_cleanup_test_');
    addTearDown(() => dir.delete(recursive: true));
    final recent = File('${dir.path}/smb_recent.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final old = File('${dir.path}/nextcloud_old.jpg')
      ..writeAsBytesSync([1, 2, 3])
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    final unrelated = File('${dir.path}/notes.txt')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));

    await clearNetworkCache(directory: dir);

    expect(recent.existsSync(), isTrue);
    expect(old.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });

  test('clearNetworkCache does not run while the small photo worker runs',
      () async {
    final dir = await Directory.systemTemp.createTemp('cache_cleanup_test_');
    addTearDown(() => dir.delete(recursive: true));
    final old = File('${dir.path}/smb_old.jpg')
      ..writeAsBytesSync([1, 2, 3])
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));

    await clearNetworkCache(directory: dir, isWorkerRunning: () => true);

    expect(old.existsSync(), isTrue);
  });
}

/// Lists its photos on the first crawl only, so a background refresh finds
/// nothing new and leaves the pool as it is. With [unreadable], every fetch
/// fails, as for a removed file.
class _OnceListedSource extends MockPhotoSource {
  _OnceListedSource({this.unreadable = false})
      : super(
          id: 'mock-once',
          folderCount: 1,
          itemsPerFolder: 2,
          simulatedDelay: Duration.zero,
        );

  final bool unreadable;
  bool _listed = false;

  @override
  Stream<Result<PhotoFolder>> listFolders({
    PhotoFolder? parent,
    CancellationToken? token,
  }) {
    if (_listed) return const Stream<Result<PhotoFolder>>.empty();
    _listed = true;
    return super.listFolders(parent: parent, token: token);
  }

  @override
  Future<Result<File>> fetchToCache(
    PhotoItem item, {
    CancellationToken? token,
  }) async {
    if (unreadable) return Result<File>.err(const NotFound('Datei fehlt'));
    return super.fetchToCache(item, token: token);
  }
}

/// Only prepared small copies are shown (the default), one slide per second.
class _PreparedOnlySettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings(
        transition: SlideshowTransition.fade,
        intervalSeconds: 1,
      );
}

/// Raw downloads are allowed too, one slide per second.
class _RawSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings(
        transition: SlideshowTransition.fade,
        onlyPreparedPhotos: false,
        intervalSeconds: 1,
      );
}

/// The slideshow screen with one [source] and the stand-ins the screen tests
/// above use (no file system, no wakelock, no kiosk channel, no worker).
ProviderScope _screenWith(
  PhotoSource source,
  AppSettingsController Function() settings,
) {
  return ProviderScope(
    overrides: [
      sourcesProvider.overrideWith(() => _FixedSourcesController([source])),
      settingsProvider.overrideWith(settings),
      alwaysOnControllerProvider.overrideWithValue(
        AlwaysOnController(wakelock: _FakeWakelock()),
      ),
      kioskModeControllerProvider
          .overrideWithValue(_FakeKioskModeController()),
      networkCacheCleanerProvider.overrideWithValue(() async {}),
      smallPhotoCacheProvider.overrideWithValue(_NoSmallPhotoCache()),
      smallPhotoWorkerProvider.overrideWith(_NoWorker.new),
      photoIndexStoreProvider.overrideWithValue(PhotoIndexStore(
        read: () async => null,
        write: (_) async {},
      )),
    ],
    child: const MaterialApp(home: SlideshowScreen()),
  );
}

/// Test stand-in: no prepared small files, no file-system access.
class _NoSmallPhotoCache extends SmallPhotoCache {
  _NoSmallPhotoCache() : super(directory: () async => Directory.systemTemp);

  @override
  Future<File?> existing(PhotoItem item) async => null;
}

/// Test stand-in: does not prepare copies (its timers would outlive the test).
class _NoWorker extends SmallPhotoWorker {
  @override
  Future<void> start(
    List<PhotoItem> items,
    Map<String, PhotoSource> sourcesById,
  ) async {}
}
