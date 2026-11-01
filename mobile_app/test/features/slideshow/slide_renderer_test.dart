import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/errors/failure.dart';
import 'package:mobile_app/core/utils/cancellation_token.dart';
import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/index/source_indexer.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/features/slideshow/domain/slideshow_config.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/slide_renderer.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
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
    final PhotoItem item = _itemFor(junk);

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

  testWidgets(
      'by default a photo without a small copy is skipped, not shown raw',
      (tester) async {
    final junk = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('slide_renderer_test_');
      return File('${dir.path}/raw.jpg').writeAsBytes(List<int>.filled(64, 7));
    });
    addTearDown(() => junk!.parent.delete(recursive: true));
    final source = _FileSource(junk!);
    addTearDown(source.dispose);
    final reasons = <SlideUnavailableReason>[];

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
            item: _itemFor(junk),
            source: source,
            displayMode: DisplayMode.cover,
            onUnavailable: reasons.add,
          ),
        ),
      ),
    ));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    // Not an error: the copy is simply not prepared yet, so the caller keeps
    // the photo and tries it again later.
    expect(reasons, [SlideUnavailableReason.notPreparedYet]);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
      'a late failure for the previous item does not skip the current one',
      (tester) async {
    final source = _GatedSource();
    addTearDown(source.dispose);
    final items = await tester.runAsync(() => crawlSource(source));
    final first = items![0];
    final second = items[1];
    final current = ValueNotifier<PhotoItem>(first);
    addTearDown(current.dispose);
    final skipped = <String>[];

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
          body: ValueListenableBuilder<PhotoItem>(
            valueListenable: current,
            builder: (context, item, _) => SlideRenderer(
              item: item,
              source: source,
              displayMode: DisplayMode.cover,
              onUnavailable: (_) => skipped.add(item.id),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(source.hasRequested(first), isTrue);

    // The slideshow moves on while the first photo is still being fetched.
    current.value = second;
    await tester.pump();
    expect(source.hasRequested(second), isTrue);

    // The first fetch fails late: it must not skip the photo on screen now.
    source
        .gateFor(first)
        .complete(Result<File>.err(const NotFound('Datei fehlt')));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(skipped, isEmpty);

    // The current photo failing is reported as usual.
    source
        .gateFor(second)
        .complete(Result<File>.err(const NotFound('Datei fehlt')));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(skipped, [second.id]);
  });

  testWidgets('a truncated raw JPEG is not shown and the photo is skipped',
      (tester) async {
    // A JPEG start without its end marker, as left behind by a cut-off download.
    final truncated = await _writeFile(tester, 'truncated.jpg', [
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      ...List<int>.filled(2000, 0x11),
    ]);
    final reasons = await _pumpRawRenderer(
      tester,
      file: truncated,
      item: _itemFor(truncated),
      displayMode: DisplayMode.cover,
    );

    expect(reasons, [SlideUnavailableReason.unreadable]);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
      'a truncated raw file smaller than the reported size is not shown',
      (tester) async {
    // The bytes are complete as far as the file goes, but the source reported a
    // larger original, so the download was cut off.
    final short = await _writeFile(tester, 'short.jpg', [
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      ...List<int>.filled(500, 0x22),
      0xFF,
      0xD9,
    ]);
    final reasons = await _pumpRawRenderer(
      tester,
      file: short,
      item: _itemFor(short, size: 4000),
      displayMode: DisplayMode.cover,
    );

    expect(reasons, [SlideUnavailableReason.unreadable]);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a complete raw JPEG is shown', (tester) async {
    final complete = await _writeFile(tester, 'complete.jpg', [
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      ...List<int>.filled(2000, 0x11),
      0xFF,
      0xD9,
    ]);
    final reasons = await _pumpRawRenderer(
      tester,
      file: complete,
      item: _itemFor(complete),
      displayMode: DisplayMode.cover,
    );

    expect(reasons, isEmpty);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
      'the blurred backdrop foreground fills the screen for a portrait photo',
      (tester) async {
    final junk =
        await _writeFile(tester, 'portrait.jpg', List<int>.filled(64, 7));
    await _pumpRawRenderer(
      tester,
      file: junk,
      item: _itemFor(junk, width: 1000, height: 1500),
      displayMode: DisplayMode.blurredBackdrop,
    );

    // The foreground is the last Image: it is painted after the blurred backdrop.
    final foreground = tester.getSize(find.byType(Image).last);
    final screen = tester.getSize(find.byType(SlideRenderer));
    expect(foreground, screen);
    // A fixed 16:9 box would be only 450 pixels high on this 800x600 screen.
    expect(foreground.height, greaterThan(screen.width * 9 / 16));
  });

  testWidgets(
      'the blurred backdrop foreground fills the screen for a landscape photo',
      (tester) async {
    final junk =
        await _writeFile(tester, 'landscape.jpg', List<int>.filled(64, 7));
    await _pumpRawRenderer(
      tester,
      file: junk,
      item: _itemFor(junk, width: 3000, height: 2000),
      displayMode: DisplayMode.blurredBackdrop,
    );

    final foreground = tester.getSize(find.byType(Image).last);
    final screen = tester.getSize(find.byType(SlideRenderer));
    expect(foreground, screen);
  });

  testWidgets('contain and cover modes still fill the screen', (tester) async {
    final junk = await _writeFile(tester, 'modes.jpg', List<int>.filled(64, 7));
    for (final mode in [DisplayMode.contain, DisplayMode.cover]) {
      await _pumpRawRenderer(
        tester,
        file: junk,
        item: _itemFor(junk, width: 1000, height: 1500),
        displayMode: mode,
      );
      final image = tester.getSize(find.byType(Image));
      final screen = tester.getSize(find.byType(SlideRenderer));
      expect(image, screen, reason: '$mode');
    }
  });
}

/// Writes [bytes] to a fresh file in a temporary directory (real I/O, so it
/// runs outside the fake-async zone) and removes the directory afterwards.
Future<File> _writeFile(
    WidgetTester tester, String name, List<int> bytes) async {
  final file = await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('slide_renderer_test_');
    return File('${dir.path}/$name').writeAsBytes(bytes);
  });
  addTearDown(() => file!.parent.delete(recursive: true));
  return file!;
}

/// A photo whose reported size matches [file], so the completeness check sees
/// the whole file. [size] overrides it, for a file that is cut off.
PhotoItem _itemFor(File file, {int? size, int? width, int? height}) =>
    PhotoItem(
      id: file.uri.pathSegments.last,
      sourceId: 'test-source',
      folderId: '',
      name: file.uri.pathSegments.last,
      mediaType: MediaType.image,
      size: size ?? file.lengthSync(),
      mtime: DateTime(2024),
      width: width,
      height: height,
    );

/// Shows [item] raw (no small copies, raw download allowed) and waits until the
/// fetch has finished. Returns the reasons the slide was reported unavailable.
Future<List<SlideUnavailableReason>> _pumpRawRenderer(
  WidgetTester tester, {
  required File file,
  required PhotoItem item,
  required DisplayMode displayMode,
}) async {
  final source = _FileSource(file);
  addTearDown(source.dispose);
  final reasons = <SlideUnavailableReason>[];
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
          displayMode: displayMode,
          onUnavailable: reasons.add,
        ),
      ),
    ),
  ));
  // The file check and the decode run on real I/O, so wait in real time.
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  return reasons;
}

/// Each fetch waits for a gate the test completes by hand, so the order in
/// which the fetches finish can be chosen.
class _GatedSource extends MockPhotoSource {
  _GatedSource() : super(simulatedDelay: Duration.zero);

  final Map<String, Completer<Result<File>>> _gates = {};

  Completer<Result<File>> gateFor(PhotoItem item) =>
      _gates.putIfAbsent(item.id, () => Completer<Result<File>>());

  bool hasRequested(PhotoItem item) => _gates.containsKey(item.id);

  @override
  Future<Result<File>> fetchToCache(
    PhotoItem item, {
    CancellationToken? token,
  }) =>
      gateFor(item).future;
}
