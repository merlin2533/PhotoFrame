import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/clock_overlay.dart';

void main() {
  testWidgets('clock shows the minute and changes only at the minute boundary',
      (tester) async {
    // Fake time: the timer runs on the test's fake clock, the displayed time
    // comes from this variable.
    var fakeNow = DateTime(2026, 11, 2, 10, 0, 50);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ClockText(now: () => fakeNow)),
    ));
    expect(find.text('10:00'), findsOneWidget);

    // Still inside the same minute: nothing changes.
    fakeNow = DateTime(2026, 11, 2, 10, 0, 55);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('10:00'), findsOneWidget);

    // The next minute boundary (about 10 s after the start) updates the text.
    fakeNow = DateTime(2026, 11, 2, 10, 1, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('10:01'), findsOneWidget);
    expect(find.text('10:00'), findsNothing);
  });

  testWidgets('disposing the clock cancels its timer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ClockText(now: () => DateTime(2026, 11, 2, 10, 0, 50)),
      ),
    ));
    // Replacing the widget disposes the clock. The test framework fails the
    // test if a timer is still pending afterwards.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(minutes: 2));
  });
}
