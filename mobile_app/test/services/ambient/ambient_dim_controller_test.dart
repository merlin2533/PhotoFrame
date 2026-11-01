import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/ambient/ambient_dim_controller.dart';

void main() {
  group('AmbientDimController mapping and hysteresis', () {
    test('starts bright with zero opacity', () {
      final c = AmbientDimController();
      expect(c.isDark, isFalse);
      expect(c.opacity, 0);
    });

    test('bright light gives no dimming', () {
      final c = AmbientDimController();
      expect(c.update(100), 0);
      expect(c.isDark, isFalse);
    });

    test('dims once lux drops below 5', () {
      final c = AmbientDimController();
      c.update(10);
      expect(c.update(4.9), greaterThan(0));
      expect(c.isDark, isTrue);
    });

    test('exactly 5 lux is not yet dark', () {
      final c = AmbientDimController();
      expect(c.update(5), 0);
      expect(c.isDark, isFalse);
    });

    test('opacity is maxOpacity (0.8) in total darkness', () {
      final c = AmbientDimController();
      expect(c.update(0), closeTo(0.8, 1e-9));
    });

    test('opacity decreases as lux rises while dark', () {
      final c = AmbientDimController();
      final darker = c.update(1);
      final brighter = c.update(4);
      expect(brighter, lessThan(darker));
      expect(brighter, greaterThanOrEqualTo(0));
      expect(darker, lessThanOrEqualTo(0.8));
    });

    test('hysteresis: stays dark between 5 and 20 lux', () {
      final c = AmbientDimController();
      c.update(1); // dark
      expect(c.update(10), greaterThan(0));
      expect(c.isDark, isTrue);
      expect(c.update(20), closeTo(0, 1e-9)); // still dark at exactly 20
      expect(c.isDark, isTrue);
    });

    test('restores brightness only above 20 lux', () {
      final c = AmbientDimController();
      c.update(1);
      expect(c.update(20.5), 0);
      expect(c.isDark, isFalse);
    });

    test('after restoring, 10 lux does not dim again (no flicker)', () {
      final c = AmbientDimController();
      c.update(1);
      c.update(25); // bright
      expect(c.update(10), 0);
      expect(c.isDark, isFalse);
    });

    test('NaN reading is ignored', () {
      final c = AmbientDimController();
      c.update(1);
      final before = c.opacity;
      expect(c.update(double.nan), before);
      expect(c.isDark, isTrue);
    });

    test('reset returns to bright', () {
      final c = AmbientDimController();
      c.update(1);
      c.reset();
      expect(c.isDark, isFalse);
      expect(c.opacity, 0);
    });
  });

  group('isWithinDimWindow', () {
    DateTime at(int hour, int minute) => DateTime(2026, 1, 15, hour, minute);

    test('midnight-crossing window 22:00-06:00', () {
      bool inside(DateTime t) => isWithinDimWindow(t,
          startMinutes: 22 * 60, endMinutes: 6 * 60);
      expect(inside(at(23, 0)), isTrue);
      expect(inside(at(5, 0)), isTrue);
      expect(inside(at(22, 0)), isTrue); // start is inclusive
      expect(inside(at(6, 0)), isFalse); // end is exclusive
      expect(inside(at(12, 0)), isFalse);
      expect(inside(at(21, 59)), isFalse);
    });

    test('same-day window 09:00-17:00', () {
      bool inside(DateTime t) => isWithinDimWindow(t,
          startMinutes: 9 * 60, endMinutes: 17 * 60);
      expect(inside(at(12, 0)), isTrue);
      expect(inside(at(8, 59)), isFalse);
      expect(inside(at(17, 0)), isFalse);
      expect(inside(at(23, 0)), isFalse);
    });

    test('equal start and end is an empty window', () {
      expect(
        isWithinDimWindow(at(12, 0),
            startMinutes: 600, endMinutes: 600),
        isFalse,
      );
    });
  });
}
