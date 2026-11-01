import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/byte_format.dart';

const _kib = 1024;
const _mib = 1024 * 1024;
const _gib = 1024 * 1024 * 1024;

void main() {
  test('sizes below 1 MB are whole kilobytes', () {
    expect(formatBytes(0, 'de'), '0 KB');
    expect(formatBytes(512 * _kib, 'de'), '512 KB');
    expect(formatBytes(_mib - 1, 'en'), '1023 KB');
  });

  test('sizes in MB and GB have one decimal, with the locale separator', () {
    final twelvePointThree = (12.3 * _mib).round();
    expect(formatBytes(twelvePointThree, 'de'), '12,3 MB');
    expect(formatBytes(twelvePointThree, 'en'), '12.3 MB');
    expect(formatBytes(2 * _gib, 'de'), '2,0 GB');
    expect(formatBytes(2 * _gib, 'en'), '2.0 GB');
  });

  test('an idle rate is shown as 0 MB/s', () {
    expect(formatRate(0, 'de'), '0 MB/s');
    expect(formatRate(-1, 'de'), '0 MB/s');
  });

  test('a busy rate is shown in MB/s with one decimal', () {
    expect(formatRate(2.5 * _mib, 'de'), '2,5 MB/s');
    expect(formatRate(2.5 * _mib, 'en'), '2.5 MB/s');
  });
}
