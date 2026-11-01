import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/cancellation_token.dart';
import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/index/source_indexer.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/features/slideshow/domain/slideshow_config.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/slide_renderer.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:mobile_app/l10n/app_localizations.dart';

/// Hands out one prepared file (bytes no image codec can decode) without
/// touching the disk inside the widget test's fake-async zone.
class _FileSource extends MockPhotoSource {
  _FileSource(this.file) : super(simulatedDelay: Duration.zero);

  final File file;

  @override
  Future<Result<File>> fetchToCache(
    PhotoItem item, {
    CancellationToken? token,
  }) async =>
      Result.ok(file);
}

/// No prepared small copy exists, so the renderer always uses the source.
class _NoSmallCopies extends SmallPhotoCache {
  _NoSmallCopies() : super(directory: () async => Directory.systemTemp);

  @override
  Future<File?> existing(PhotoItem item) async => null;
}

/// Settings that allow showing the raw download (the default is to show only
/// checked small copies).
class _RawAllowedSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(onlyPreparedPhotos: false);
}

/// Default settings: only prepared small copies are shown.
class _DefaultSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  testWidgets('a photo that cannot be decoded shows the localized placeholder',
      (tester) async {
    // Real file I/O has to happen outside the fake-async zone of testWidgets.
    final junk = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('slide_renderer_test_');
      return File('${dir.path}/not_an_image.jpg')
          .writeAsBytes(List<int>.filled(64, 7));
    });
    addTearDown(() => junk!.parent.delete(recursive: true));
    final source = _FileSource(junk!);
    addTearDown(source.dispose);
    final items = await tester.runAsync(() => crawlSource(source));
    final PhotoItem item = items!.first;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        smallPhotoCacheProvider.overrideWithValue(_NoSmallCopies()),
        settingsProvider.overrideWith(_RawAllowedSettings.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: SlideRenderer(
            item: item,
            source: source,
            displayMode: DisplayMode.cover,
          ),
        ),
      ),
    ));

    // The decode runs on real I/O, so the test waits in real time between
    // frames until the error placeholder appears.
    final reason = find.textContaining('Nicht dekodierbar');
    for (var i = 0; i < 200 && reason.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(reason, findsOneWidget);
  });

  testWidgets('by default a photo without a small copy is skipped, not shown raw',
      (tester) async {
    final junk = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('slide_renderer_test_');
      return File('${dir.path}/raw.jpg').writeAsBytes(List<int>.filled(64, 7));
    });
    addTearDown(() => junk!.parent.delete(recursive: true));
    final source = _FileSource(junk!);
    addTearDown(source.dispose);
    final items = await tester.runAsync(() => crawlSource(source));
    var unavailable = 0;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        smallPhotoCacheProvider.overrideWithValue(_NoSmallCopies()),
        settingsProvider.overrideWith(_DefaultSettings.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: SlideRenderer(
            item: items!.first,
            source: source,
            displayMode: DisplayMode.cover,
            onUnavailable: () => unavailable++,
          ),
        ),
      ),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(unavailable, 1);
    expect(find.byType(Image), findsNothing);
  });
}
