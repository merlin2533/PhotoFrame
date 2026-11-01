/// Measures the download speed over a sliding window from cumulative byte
/// counts sampled over time.
///
/// Each [add] records the total bytes downloaded at a moment. [bytesPerSecond]
/// compares the newest sample with the baseline sample: the newest sample at
/// or before the start of the window, or the oldest sample while the window is
/// not yet full. The result is the average over roughly the last [window].
/// When no bytes arrive for a whole window the two samples are equal and the
/// rate is 0.
class DownloadRateMeter {
  DownloadRateMeter({this.window = const Duration(seconds: 10)});

  /// Length of the averaging window.
  final Duration window;

  /// Ordered by time. Besides the samples inside the window, only the newest
  /// sample at or before the window start is kept, as the baseline.
  final List<_Sample> _samples = [];

  /// Forgets all samples.
  void reset() => _samples.clear();

  /// Records that [totalBytes] had been downloaded at [at]. Samples must be
  /// added in time order.
  void add(DateTime at, int totalBytes) {
    _samples.add(_Sample(at, totalBytes));
    final cutoff = at.subtract(window);
    // Drop the oldest sample while the second one is still at or before the
    // cutoff: the remaining first sample is the baseline of the window.
    while (_samples.length >= 2 && !_samples[1].at.isAfter(cutoff)) {
      _samples.removeAt(0);
    }
  }

  /// Average download speed in bytes per second over the window. `0` when
  /// there are fewer than two samples or nothing was downloaded.
  double get bytesPerSecond {
    if (_samples.length < 2) return 0;
    final baseline = _samples.first;
    final newest = _samples.last;
    final seconds = newest.at.difference(baseline.at).inMicroseconds / 1e6;
    if (seconds <= 0) return 0;
    final bytes = newest.totalBytes - baseline.totalBytes;
    return bytes <= 0 ? 0 : bytes / seconds;
  }
}

class _Sample {
  const _Sample(this.at, this.totalBytes);

  final DateTime at;
  final int totalBytes;
}
