import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/slideshow/domain/always_on_controller.dart';
import 'package:mobile_app/features/slideshow/presentation/slideshow_screen.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/empty_state_view.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/slide_renderer.dart';
import 'package:mobile_app/features/slideshow/state/slideshow_providers.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:mobile_app/features/sources/state/sources_providers.dart';
import 'package:mobile_app/services/kiosk/kiosk_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('shows the empty state when no photo source is configured', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SlideshowScreen(),
        overrides: [
          sourcesProvider.overrideWith(() => _FixedSourcesController(const [])),
          alwaysOnControllerProvider.overrideWithValue(
            AlwaysOnController(wakelock: _FakeWakelock()),
          ),
          kioskModeControllerProvider.overrideWithValue(_FakeKioskModeController()),
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

  testWidgets('renders the current item once a MockPhotoSource is registered', (tester) async {
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
          alwaysOnControllerProvider.overrideWithValue(
            AlwaysOnController(wakelock: _FakeWakelock()),
          ),
          kioskModeControllerProvider.overrideWithValue(kiosk),
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
    expect(find.textContaining('mock_0_'), findsOneWidget);

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
}
