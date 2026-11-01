import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:mobile_app/features/slideshow/domain/daily_selection.dart';
import 'package:mobile_app/features/slideshow/presentation/slideshow_screen.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/empty_state_view.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/preparing_view.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/slide_renderer.dart';
import 'package:mobile_app/features/slideshow/state/slideshow_providers.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_folder.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:mobile_app/features/sources/state/sources_providers.dart';
import 'package:mobile_app/l10n/app_localizations.dart';
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
    // Fixed time instead of pumpAndSettle: the background timers of the
    // slideshow never let the tree settle, but the first slide is ready here.
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(EmptyStateView), findsNothing);
    // During a fade two slides can be mounted at once, so only require that a
    // slide is shown.
    expect(find.byType(SlideRenderer), findsWidgets);
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

  testWidgets(
      'shows the preparing view while the start waits for prepared copies',
      (tester) async {
    final source = _mockWithOneSavedItem();
    await tester.pumpWidget(_screenWith(
      source,
      _PreparedOnlySettings.new,
      savedItems: _savedItemsOf(source),
      preparedWaitLimit: const Duration(seconds: 1),
    ));
    await _pumpUntilPreparing(tester);

    expect(find.byType(PreparingView), findsOneWidget);
    expect(find.text('Diashow wird vorbereitet'), findsOneWidget);
    // No worker progress yet (total 0): indeterminate bar, placeholder text.
    expect(find.text('Fotos werden vorbereitet…'), findsOneWidget);
    expect(find.byType(EmptyStateView), findsNothing);
    // The action buttons of the empty state stay available.
    expect(find.byTooltip('Neu laden'), findsOneWidget);
    expect(find.byTooltip('Einstellungen'), findsOneWidget);

    // Wait limit over: no prepared copy ever appeared, so no engine starts.
    // The flag clears and the empty state comes back.
    await _passWaitLimit(tester);
    expect(find.byType(PreparingView), findsNothing);
    expect(find.byType(EmptyStateView), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the preparing view shows the small photo worker progress',
      (tester) async {
    final source = _mockWithOneSavedItem();
    await tester.pumpWidget(_screenWith(
      source,
      _PreparedOnlySettings.new,
      savedItems: _savedItemsOf(source),
      preparedWaitLimit: const Duration(seconds: 1),
      worker: _ProgressWorker.new,
    ));
    await _pumpUntilPreparing(tester);

    expect(
      find.text('2 von 5 Fotos vorbereitet · 3 in Warteschlange'),
      findsOneWidget,
    );
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.4, 1e-9));

    await _passWaitLimit(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'starts at once with a prepared photo of the index when the selection has none',
      (tester) async {
    final source = MockPhotoSource(
      id: 'mock-prep',
      folderCount: 1,
      itemsPerFolder: 3,
      simulatedDelay: Duration.zero,
    );
    final items = [
      for (final id in ['a', 'b', 'c']) _itemOf(source, id)
    ];
    // The saved selection holds a and b only; c is the one prepared copy, so
    // it lies outside today's selection (the worker prepares in random order).
    SharedPreferences.setMockInitialValues({
      'daily_selection_v1': jsonEncode({
        'day': DailySelection.dayKey(DateTime.now()),
        'keys': ['mock-prep::a', 'mock-prep::b'],
      }),
    });
    final preparedDir = Directory.systemTemp.createTempSync('prepared_test_');
    addTearDown(() => preparedDir.delete(recursive: true));
    final preparedFile = File('${preparedDir.path}/c_small.jpg')
      ..writeAsBytesSync([1, 2, 3]);

    await tester.pumpWidget(_screenWith(
      source,
      _TwoPhotoSelection.new,
      savedItems: items,
      // Default wait limit (3 minutes): reaching the engine within the 1 s
      // below proves the start did not wait for the timeout.
      cache: _SomePreparedSmallPhotoCache({'c'}, preparedFile),
    ));
    for (var i = 0;
        i < 100 && find.byType(SlideRenderer).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.byType(SlideRenderer), findsWidgets);
    expect(find.byType(PreparingView), findsNothing);
    expect(find.byType(EmptyStateView), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'with preparation off the start does not wait for prepared copies',
      (tester) async {
    final source = _mockWithOneSavedItem();
    final starts = <int>[];
    await tester.pumpWidget(_screenWith(
      source,
      _PreparationOffSettings.new,
      savedItems: _savedItemsOf(source),
      // Default wait limit (3 minutes): reaching the engine within the loop
      // below proves the start did not wait for prepared copies.
      worker: () => _StartCountingWorker(starts),
    ));
    for (var i = 0;
        i < 100 && find.byType(SlideRenderer).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    // Let the background refresh (which would start the worker) run too.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.byType(SlideRenderer), findsWidgets);
    expect(find.byType(PreparingView), findsNothing);
    expect(find.byType(EmptyStateView), findsNothing);
    expect(starts, isEmpty);

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

/// Only prepared small copies are shown, and today's selection holds two of
/// the saved photos.
class _TwoPhotoSelection extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings(
        transition: SlideshowTransition.fade,
        intervalSeconds: 1,
        selectionCount: 2,
      );
}

/// Preparation switched off: raw downloads are shown, one slide per second.
class _PreparationOffSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings(
        transition: SlideshowTransition.fade,
        intervalSeconds: 1,
        smallPhotoPreparation: false,
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
///
/// [savedItems] become the saved photo index, so the start path goes through
/// `_preferPrepared`. [preparedWaitLimit] and [worker] override the defaults.
ProviderScope _screenWith(
  PhotoSource source,
  AppSettingsController Function() settings, {
  List<PhotoItem> savedItems = const [],
  Duration? preparedWaitLimit,
  SmallPhotoWorker Function()? worker,
  SmallPhotoCache? cache,
}) {
  return ProviderScope(
    overrides: [
      sourcesProvider.overrideWith(() => _FixedSourcesController([source])),
      settingsProvider.overrideWith(settings),
      alwaysOnControllerProvider.overrideWithValue(
        AlwaysOnController(wakelock: _FakeWakelock()),
      ),
      kioskModeControllerProvider.overrideWithValue(_FakeKioskModeController()),
      networkCacheCleanerProvider.overrideWithValue(() async {}),
      smallPhotoCacheProvider.overrideWithValue(cache ?? _NoSmallPhotoCache()),
      smallPhotoWorkerProvider.overrideWith(worker ?? _NoWorker.new),
      photoIndexStoreProvider.overrideWithValue(_SavedIndexStore(savedItems)),
    ],
    child: MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SlideshowScreen(
        preparedWaitLimit:
            preparedWaitLimit ?? SlideshowScreen.defaultPreparedWaitLimit,
      ),
    ),
  );
}

/// Index store that returns [items] as the saved index (none when empty).
class _SavedIndexStore extends PhotoIndexStore {
  _SavedIndexStore(this.items)
      : super(read: () async => null, write: (_) async {});

  final List<PhotoItem> items;

  @override
  Future<IndexSnapshot> load() async {
    if (items.isEmpty) return IndexSnapshot.empty;
    return IndexSnapshot(items: items, savedAt: DateTime.now());
  }
}

/// Test stand-in: only the photos in [preparedIds] have a small copy, all of
/// them the file [file]. Its bytes are not an image, so the slide shows its
/// placeholder.
class _SomePreparedSmallPhotoCache extends SmallPhotoCache {
  _SomePreparedSmallPhotoCache(this.preparedIds, this.file)
      : super(directory: () async => Directory.systemTemp);

  final Set<String> preparedIds;
  final File file;

  @override
  Future<File?> existing(PhotoItem item) async =>
      preparedIds.contains(item.id) ? file : null;

  @override
  Future<File?> verifiedExisting(PhotoItem item) async =>
      preparedIds.contains(item.id) ? file : null;
}

/// Test stand-in worker reporting fixed progress (2 of 5 prepared).
class _ProgressWorker extends _NoWorker {
  @override
  SmallPhotoStatus build() =>
      const SmallPhotoStatus(done: 2, total: 5, running: true, waiting: 3);
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

/// Like [_NoWorker], but records the size of every queue handed to [start].
class _StartCountingWorker extends _NoWorker {
  _StartCountingWorker(this.starts);

  final List<int> starts;

  @override
  Future<void> start(
    List<PhotoItem> items,
    Map<String, PhotoSource> sourcesById,
  ) async {
    starts.add(items.length);
  }
}

/// A mock source for the start-path tests; nothing in it is ever prepared.
MockPhotoSource _mockWithOneSavedItem() => MockPhotoSource(
      id: 'mock-prep',
      folderCount: 1,
      itemsPerFolder: 1,
      simulatedDelay: Duration.zero,
    );

/// One saved index entry for [source], so the start path waits for prepared
/// copies (see `_preferPrepared`).
List<PhotoItem> _savedItemsOf(PhotoSource source) => [
      PhotoItem(
        id: 'folder-0-item-0',
        sourceId: source.id,
        folderId: 'folder-0',
        name: 'mock_0_0.jpg',
        mediaType: MediaType.image,
        size: 1,
        mtime: DateTime(2024),
        width: 1920,
        height: 1080,
        takenAt: DateTime(2024),
      ),
    ];

/// A saved index entry with the id [id] in [source].
PhotoItem _itemOf(PhotoSource source, String id) => PhotoItem(
      id: id,
      sourceId: source.id,
      folderId: 'folder-0',
      name: 'mock_0_$id.jpg',
      mediaType: MediaType.image,
      size: 1,
      mtime: DateTime(2024),
      width: 1920,
      height: 1080,
      takenAt: DateTime(2024),
    );

/// Pumps until the preparing view is on screen (the start path reaches the
/// wait after a few async steps).
Future<void> _pumpUntilPreparing(WidgetTester tester) async {
  for (var i = 0;
      i < 100 && find.byType(PreparingView).evaluate().isEmpty;
      i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Lets the wait run out. Its deadline is measured with `DateTime.now()`,
/// which the fake clock of `testWidgets` does not move, so real time has to
/// pass first; the wait's 3 s poll then ends it.
Future<void> _passWaitLimit(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1100)));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
}
