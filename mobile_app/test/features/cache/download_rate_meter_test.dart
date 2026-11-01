import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/download_rate_meter.dart';

const _mib = 1024 * 1024;

void main() {
  final start = DateTime(2026, 1, 1, 12);

  test('without samples the rate is 0', () {
    expect(DownloadRateMeter().bytesPerSecond, 0);
  });

  test('a single sample gives no rate yet', () {
    final meter = DownloadRateMeter()..add(start, 5 * _mib);
    expect(meter.bytesPerSecond, 0);
  });

  test('steady downloads average to their speed', () {
    final meter = DownloadRateMeter();
    for (var s = 0; s <= 5; s++) {
      meter.add(start.add(Duration(seconds: s)), s * _mib);
    }
    expect(meter.bytesPerSecond, closeTo(_mib.toDouble(), 1e-6));
  });

  test('the rate falls to 0 once nothing is downloaded for a window', () {
    final meter = DownloadRateMeter();
    // 1 MB per second for 30 seconds, then the downloads stop at 30 MB.
    for (var s = 0; s <= 30; s++) {
      meter.add(start.add(Duration(seconds: s)), s * _mib);
    }
    for (var s = 31; s <= 40; s++) {
      meter.add(start.add(Duration(seconds: s)), 30 * _mib);
    }
    // The window now starts at second 30, which had 30 MB: nothing arrived.
    expect(meter.bytesPerSecond, 0);
  });

  test('only the last window counts, so an old slow phase is forgotten', () {
    final meter = DownloadRateMeter();
    // 1 MB per second up to second 30, then nothing until second 35.
    for (var s = 0; s <= 30; s++) {
      meter.add(start.add(Duration(seconds: s)), s * _mib);
    }
    for (var s = 31; s <= 35; s++) {
      meter.add(start.add(Duration(seconds: s)), 30 * _mib);
    }
    // Window starts at second 25 (25 MB): 5 MB in 10 seconds.
    expect(meter.bytesPerSecond, closeTo(0.5 * _mib, 1e-6));
  });

  test('the samples kept stay bounded by the window', () {
    final meter = DownloadRateMeter(window: const Duration(seconds: 10));
    for (var s = 0; s <= 1000; s++) {
      meter.add(start.add(Duration(seconds: s)), s * 1000);
    }
    // Still 1000 bytes per second after a long run.
    expect(meter.bytesPerSecond, closeTo(1000, 1e-6));
  });

  test('reset forgets all samples', () {
    final meter = DownloadRateMeter();
    meter.add(start, 0);
    meter.add(start.add(const Duration(seconds: 1)), _mib);
    meter.reset();
    expect(meter.bytesPerSecond, 0);
  });
}
