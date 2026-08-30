import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/services/cache/image_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<File> _writeTempFile(Directory dir, String name, int sizeBytes) async {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(List<int>.filled(sizeBytes, 1));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('cache_info_provider_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('cacheInfoProvider starts at 0 used bytes with the configured limit', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Let the async settings load complete so cacheLimitBytes reflects the
    // real default rather than the AsyncValue.loading() fallback.
    await container.read(settingsProvider.future);

    final info = container.read(cacheInfoProvider);
    expect(info.usedBytes, 0);
    expect(info.limitBytes, const AppSettings().cacheLimitBytes);
  });

  test('cacheInfoProvider reflects bytes actually stored in ImageCacheManager', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);

    final manager = container.read(imageCacheManagerProvider);
    final file = await _writeTempFile(tempDir, 'a.jpg', 1000);
    await manager.put('a', file, tier: CacheTier.full);

    // The manager mutates its own state without notifying Riverpod -
    // `cacheInfoProvider` (a plain Provider) must be re-read, not just
    // watched, to pick up the change; this mirrors what
    // `cache_settings_screen.dart` does via `ref.invalidate`.
    container.invalidate(cacheInfoProvider);
    final info = container.read(cacheInfoProvider);
    expect(info.usedBytes, 1000);
  });

  test('imageCacheManagerProvider re-enforces a lowered limit on settings change', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);

    final manager = container.read(imageCacheManagerProvider);
    final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
    final f2 = await _writeTempFile(tempDir, 'b.jpg', 100);
    await manager.put('a', f1, tier: CacheTier.full);
    await manager.put('b', f2, tier: CacheTier.full);
    expect(manager.currentSizeBytes(CacheTier.full), 200);

    // Shrink the overall cache limit down to something that can't fit both
    // full-tier entries any more (full tier gets 85% of the total per the
    // provider's split, so a 100-byte total limit leaves ~85 bytes for the
    // full tier - not enough for either 100-byte file).
    await container.read(settingsProvider.notifier).updateSettings(
          (s) => s.copyWith(cacheLimitBytes: 100),
        );

    // The `ref.listen` callback fires synchronously on the settings change,
    // but `setLimitBytes` -> `_enforceLimit` -> `effectiveLimitBytes` awaits
    // a (mocked-away, plugin-less) platform channel round trip for free
    // disk space before evicting - poll with a generous deadline instead of
    // guessing a fixed microtask/delay count.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (manager.currentSizeBytes(CacheTier.full) >= 200 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(manager.currentSizeBytes(CacheTier.full), lessThan(200));
  });
}
