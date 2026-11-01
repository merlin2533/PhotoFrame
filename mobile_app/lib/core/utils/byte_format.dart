import 'package:intl/intl.dart';

const _kib = 1024;
const _mib = 1024 * 1024;
const _gib = 1024 * 1024 * 1024;

/// Human readable size: whole KB below 1 MB, one decimal in MB and GB (base
/// 1024). The decimal separator follows [locale], for example `2,4 MB` in
/// German.
String formatBytes(int bytes, String locale) {
  if (bytes < _mib) {
    return '${bytes ~/ _kib} KB';
  }
  if (bytes < _gib) {
    return '${_decimal(bytes / _mib, locale)} MB';
  }
  return '${_decimal(bytes / _gib, locale)} GB';
}

/// Download speed in MB/s with one decimal. An idle download (zero or
/// negative) is shown as `0 MB/s`.
String formatRate(double bytesPerSecond, String locale) {
  if (bytesPerSecond <= 0) return '0 MB/s';
  return '${_decimal(bytesPerSecond / _mib, locale)} MB/s';
}

String _decimal(double value, String locale) =>
    NumberFormat('#,##0.0', locale).format(value);
