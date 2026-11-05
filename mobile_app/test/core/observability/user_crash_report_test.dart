import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/observability/error_reporter.dart';
import 'package:mobile_app/core/observability/user_crash_report.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crash_report_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('counts and sizes come from the cache folder, file names do not leak',
      () async {
    // Two copies of source "src1" (16 hex digits, as the cache writes them)
    // and one unassigned file with a photo name.
    File('${tempDir.path}/src1_0123456789abcdef.jpg')
        .writeAsBytesSync(List.filled(10, 1));
    File('${tempDir.path}/src1_fedcba9876543210.jpg')
        .writeAsBytesSync(List.filled(20, 1));
    File('${tempDir.path}/IMG_9999.jpg').writeAsBytesSync(List.filled(5, 1));
    final usage = await SmallPhotoCache(directory: () async => tempDir)
        .usage(const ['src1']);

    final data = buildUserCrashReportData(
      appVersion: '0.1.0',
      build: '14',
      deviceModel: 'Pixel 9 Pro XL',
      androidVersion: '16',
      cacheFiles: usage.count,
      cacheBytes: usage.totalBytes,
      cacheLimitBytes: 500 * 1024 * 1024,
      preparationEnabled: true,
      sourceCount: 1,
      traceLines: const ['2026-11-05T10:00:00 slide tick', 'cache ok'],
    );

    expect(
        data.keys,
        unorderedEquals([
          'app_version',
          'build',
          'device_model',
          'android_version',
          'cache_files',
          'cache_bytes',
          'cache_limit_bytes',
          'preparation_enabled',
          'source_count',
          'trace',
        ]));
    expect(data['app_version'], '0.1.0');
    expect(data['build'], '14');
    expect(data['device_model'], 'Pixel 9 Pro XL');
    expect(data['android_version'], '16');
    expect(data['cache_files'], 3);
    expect(data['cache_bytes'], 35);
    expect(data['cache_limit_bytes'], 500 * 1024 * 1024);
    expect(data['preparation_enabled'], isTrue);
    expect(data['source_count'], 1);
    expect(data['trace'], '2026-11-05T10:00:00 slide tick\ncache ok');

    final text = data.toString();
    expect(text, isNot(contains('IMG_9999')));
    expect(text, isNot(contains('src1_')));
    expect(text, isNot(contains(tempDir.path)));
  });

  test('the shared beforeSend scrubbing removes names from the report context',
      () async {
    setErrorReportingEnabled(true);
    final event = SentryEvent(
      message: SentryMessage(kUserCrashReportMessage),
    );
    event.contexts[kUserCrashReportContext] = buildUserCrashReportData(
      appVersion: '0.1.0',
      build: '14',
      deviceModel: 'Pixel 9 Pro XL',
      androidVersion: '16',
      cacheFiles: 1,
      cacheBytes: 5,
      cacheLimitBytes: 1,
      preparationEnabled: false,
      sourceCount: 2,
      traceLines: const [
        'slide image.file /storage/emulated/0/Urlaub/IMG_1.jpg',
        'source host "nas.local" https://nas.local/share/IMG_2.jpg',
      ],
    );

    final scrubbed = (await redactSentryEvent(event, Hint()))!;
    final text = scrubbed.contexts[kUserCrashReportContext].toString();

    expect(text, isNot(contains('IMG_1')));
    expect(text, isNot(contains('IMG_2')));
    expect(text, isNot(contains('nas.local')));
    expect(text, isNot(contains('/storage')));
    expect(text, contains('cache_files: 1'));
    expect(text, contains('source_count: 2'));
  });

  test('the event message is the fixed user crash report text', () {
    expect(kUserCrashReportMessage, 'User crash report');
    expect(kUserCrashReportTraceLines, 200);
  });
}
