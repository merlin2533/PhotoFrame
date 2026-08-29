import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/slideshow/domain/always_on_controller.dart';
import 'package:mobile_app/features/slideshow/domain/night_schedule.dart';
import 'package:mocktail/mocktail.dart';

class _MockWakelockController extends Mock implements WakelockController {}

void main() {
  late _MockWakelockController wakelock;

  setUp(() {
    wakelock = _MockWakelockController();
    when(() => wakelock.enable()).thenAnswer((_) async {});
    when(() => wakelock.disable()).thenAnswer((_) async {});
  });

  test('constructor does not touch the platform wakelock', () {
    AlwaysOnController(wakelock: wakelock);
    verifyNever(() => wakelock.enable());
    verifyNever(() => wakelock.disable());
  });

  group('AlwaysOnMode.always', () {
    test('enables wakelock as soon as applied, even without a slideshow', () async {
      final controller = AlwaysOnController(
        wakelock: wakelock,
        mode: AlwaysOnMode.always,
      );
      await controller.applyInitialState();
      verify(() => wakelock.enable()).called(1);
      expect(controller.isWakelockActive, isTrue);
    });
  });

  group('AlwaysOnMode.duringSlideshowOnly', () {
    test('stays disabled until slideshow starts, then enables', () async {
      final controller = AlwaysOnController(wakelock: wakelock);
      await controller.applyInitialState();
      verifyNever(() => wakelock.enable());

      await controller.onSlideshowStarted();
      verify(() => wakelock.enable()).called(1);
      expect(controller.isWakelockActive, isTrue);

      await controller.onSlideshowStopped();
      verify(() => wakelock.disable()).called(1);
      expect(controller.isWakelockActive, isFalse);
    });

    test('does not call disable again if already disabled', () async {
      final controller = AlwaysOnController(wakelock: wakelock);
      await controller.applyInitialState();
      await controller.onSlideshowStopped();
      verifyNever(() => wakelock.disable());
    });
  });

  group('AlwaysOnMode.scheduled', () {
    const daySchedule = NightSchedule(
      mode: NightScheduleMode.fixedRange,
      startHour: 22,
      startMinute: 0,
      endHour: 7,
      endMinute: 0,
    );

    test('keeps screen awake during the day while slideshow runs', () async {
      final controller = AlwaysOnController(
        wakelock: wakelock,
        mode: AlwaysOnMode.scheduled,
        nightSchedule: daySchedule,
      );
      final noon = DateTime(2026, 1, 1, 12, 0);

      await controller.onSlideshowStarted(now: noon);

      verify(() => wakelock.enable()).called(1);
      expect(controller.isWakelockActive, isTrue);
    });

    test('allows screen to sleep during the night window while slideshow runs', () async {
      final controller = AlwaysOnController(
        wakelock: wakelock,
        mode: AlwaysOnMode.scheduled,
        nightSchedule: daySchedule,
      );
      final midnight = DateTime(2026, 1, 1, 23, 30);

      await controller.onSlideshowStarted(now: midnight);

      verifyNever(() => wakelock.enable());
      expect(controller.isWakelockActive, isFalse);
    });

    test('transitions from day to night on tick without other state changes', () async {
      final controller = AlwaysOnController(
        wakelock: wakelock,
        mode: AlwaysOnMode.scheduled,
        nightSchedule: daySchedule,
      );
      final noon = DateTime(2026, 1, 1, 12, 0);
      await controller.onSlideshowStarted(now: noon);
      verify(() => wakelock.enable()).called(1);

      final night = DateTime(2026, 1, 1, 22, 30);
      await controller.tick(now: night);

      verify(() => wakelock.disable()).called(1);
      expect(controller.isWakelockActive, isFalse);
    });

    test('never wakes the screen at night if slideshow is not running', () async {
      final controller = AlwaysOnController(
        wakelock: wakelock,
        mode: AlwaysOnMode.scheduled,
        nightSchedule: daySchedule,
      );
      final night = DateTime(2026, 1, 1, 23, 0);

      await controller.applyInitialState(now: night);

      verifyNever(() => wakelock.enable());
    });
  });

  group('updateMode', () {
    test('switching from duringSlideshowOnly to always enables immediately', () async {
      final controller = AlwaysOnController(wakelock: wakelock);
      await controller.applyInitialState();
      verifyNever(() => wakelock.enable());

      await controller.updateMode(AlwaysOnMode.always);

      verify(() => wakelock.enable()).called(1);
    });
  });

  group('dispose', () {
    test('releases an active wakelock', () async {
      final controller = AlwaysOnController(
        wakelock: wakelock,
        mode: AlwaysOnMode.always,
      );
      await controller.applyInitialState();
      await controller.dispose();
      verify(() => wakelock.disable()).called(1);
    });

    test('does nothing if wakelock was never active', () async {
      final controller = AlwaysOnController(wakelock: wakelock);
      await controller.applyInitialState();
      await controller.dispose();
      verifyNever(() => wakelock.disable());
    });
  });
}
