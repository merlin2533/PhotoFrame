import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/cache/image_cache_manager.dart';

Future<File> _writeTempFile(Directory dir, String name, int sizeBytes) async {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(List<int>.filled(sizeBytes, 1));
  return file;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('image_cache_manager_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('size limit enforcement', () {
    test('evicts least-recently-used entries once the tier limit is exceeded', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 1000,
        fullLimitBytes: 250, // room for ~2 files of 100 bytes
      );

      final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
      final f2 = await _writeTempFile(tempDir, 'b.jpg', 100);
      final f3 = await _writeTempFile(tempDir, 'c.jpg', 100);

      await manager.put('a', f1, tier: CacheTier.full);
      await manager.put('b', f2, tier: CacheTier.full);
      await manager.put('c', f3, tier: CacheTier.full);

      // Adding 'c' pushes total to 300 > 250, so the LRU entry ('a') must be
      // evicted.
      expect(manager.contains('a', tier: CacheTier.full), isFalse);
      expect(manager.contains('b', tier: CacheTier.full), isTrue);
      expect(manager.contains('c', tier: CacheTier.full), isTrue);
      expect(manager.currentSizeBytes(CacheTier.full), lessThanOrEqualTo(250));
    });

    test('the two tiers are enforced independently', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 150,
        fullLimitBytes: 150,
      );
      final thumb1 = await _writeTempFile(tempDir, 't1.jpg', 100);
      final thumb2 = await _writeTempFile(tempDir, 't2.jpg', 100);
      final full1 = await _writeTempFile(tempDir, 'f1.jpg', 100);

      await manager.put('t1', thumb1, tier: CacheTier.thumbnail);
      await manager.put('t2', thumb2, tier: CacheTier.thumbnail);
      await manager.put('f1', full1, tier: CacheTier.full);

      // Thumbnail tier exceeded its own limit and evicted t1; full tier is
      // unaffected and still has f1.
      expect(manager.contains('t1', tier: CacheTier.thumbnail), isFalse);
      expect(manager.contains('t2', tier: CacheTier.thumbnail), isTrue);
      expect(manager.contains('f1', tier: CacheTier.full), isTrue);
    });

    test('caps the effective limit against injected free disk space', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 1000,
        fullLimitBytes: 10000, // configured limit is generous
        minFreeSpaceReserveBytes: 100,
        getFreeDiskSpaceBytes: () async => 250, // but disk is nearly full
      );

      // Effective limit = 250 - 100 = 150.
      expect(await manager.effectiveLimitBytes(CacheTier.full), 150);

      final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
      final f2 = await _writeTempFile(tempDir, 'b.jpg', 100);
      await manager.put('a', f1, tier: CacheTier.full);
      await manager.put('b', f2, tier: CacheTier.full);

      expect(manager.currentSizeBytes(CacheTier.full), lessThanOrEqualTo(150));
      expect(manager.contains('a', tier: CacheTier.full), isFalse);
      expect(manager.contains('b', tier: CacheTier.full), isTrue);
    });
  });

  group('pin (CacheLease) protection', () {
    test('a pinned entry is never evicted by LRU pressure', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 1000,
        fullLimitBytes: 250,
      );
      final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
      final f2 = await _writeTempFile(tempDir, 'b.jpg', 100);
      final f3 = await _writeTempFile(tempDir, 'c.jpg', 100);

      await manager.put('a', f1, tier: CacheTier.full);
      final lease = manager.acquire('a', tier: CacheTier.full);

      await manager.put('b', f2, tier: CacheTier.full);
      await manager.put('c', f3, tier: CacheTier.full);

      // 'a' is the LRU candidate but is pinned, so eviction must skip it and
      // remove the next-oldest unprotected entry ('b') instead, even though
      // that leaves the tier over its nominal limit until further eviction
      // is possible.
      expect(manager.contains('a', tier: CacheTier.full), isTrue);
      expect(manager.contains('b', tier: CacheTier.full), isFalse);
      expect(manager.contains('c', tier: CacheTier.full), isTrue);

      lease.release();
    });

    test('acquire/release is symmetric: releasing drops the pin and allows eviction again', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 1000,
        fullLimitBytes: 250,
      );
      final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
      final f2 = await _writeTempFile(tempDir, 'b.jpg', 100);
      final f3 = await _writeTempFile(tempDir, 'c.jpg', 100);

      await manager.put('a', f1, tier: CacheTier.full);
      final lease = manager.acquire('a', tier: CacheTier.full);
      expect(manager.pinCountOf('a', tier: CacheTier.full), 1);

      lease.release();
      expect(manager.pinCountOf('a', tier: CacheTier.full), 0);
      expect(lease.isReleased, isTrue);

      // Releasing again is a no-op (idempotent), not a double-decrement.
      lease.release();
      expect(manager.pinCountOf('a', tier: CacheTier.full), 0);

      await manager.put('b', f2, tier: CacheTier.full);
      await manager.put('c', f3, tier: CacheTier.full);

      // Now that 'a' is unpinned again, normal LRU eviction applies to it.
      expect(manager.contains('a', tier: CacheTier.full), isFalse);
    });

    test('multiple leases on the same key require multiple releases before eviction is allowed', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 1000,
        fullLimitBytes: 250,
      );
      final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
      final f2 = await _writeTempFile(tempDir, 'b.jpg', 100);
      final f3 = await _writeTempFile(tempDir, 'c.jpg', 100);

      await manager.put('a', f1, tier: CacheTier.full);
      final lease1 = manager.acquire('a', tier: CacheTier.full);
      final lease2 = manager.acquire('a', tier: CacheTier.full);
      expect(manager.pinCountOf('a', tier: CacheTier.full), 2);

      lease1.release();
      expect(manager.pinCountOf('a', tier: CacheTier.full), 1);

      await manager.put('b', f2, tier: CacheTier.full);
      await manager.put('c', f3, tier: CacheTier.full);
      // Still pinned once - must survive.
      expect(manager.contains('a', tier: CacheTier.full), isTrue);

      lease2.release();
      expect(manager.pinCountOf('a', tier: CacheTier.full), 0);
    });
  });

  group('offline reserve', () {
    test('the last N successfully displayed images are never evicted even when unpinned', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 1000,
        fullLimitBytes: 200,
        offlineReserveCount: 1,
      );
      final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
      final f2 = await _writeTempFile(tempDir, 'b.jpg', 100);
      final f3 = await _writeTempFile(tempDir, 'c.jpg', 100);

      await manager.put('a', f1, tier: CacheTier.full);
      manager.recordSuccessfullyDisplayed('a', tier: CacheTier.full);
      expect(manager.isOfflineReserve('a', tier: CacheTier.full), isTrue);

      await manager.put('b', f2, tier: CacheTier.full);
      await manager.put('c', f3, tier: CacheTier.full);

      // 'a' would normally be the LRU eviction candidate, but is protected
      // as the offline reserve; 'b' gets evicted instead.
      expect(manager.contains('a', tier: CacheTier.full), isTrue);
      expect(manager.contains('b', tier: CacheTier.full), isFalse);
    });

    test('the reserve slides: marking a new image as displayed frees the previous reserve slot', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 1000,
        fullLimitBytes: 1000,
        offlineReserveCount: 1,
      );
      final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
      final f2 = await _writeTempFile(tempDir, 'b.jpg', 100);

      await manager.put('a', f1, tier: CacheTier.full);
      manager.recordSuccessfullyDisplayed('a', tier: CacheTier.full);
      await manager.put('b', f2, tier: CacheTier.full);
      manager.recordSuccessfullyDisplayed('b', tier: CacheTier.full);

      expect(manager.isOfflineReserve('a', tier: CacheTier.full), isFalse);
      expect(manager.isOfflineReserve('b', tier: CacheTier.full), isTrue);
    });

    test('reserve and pin protections are independent of one another', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 1000,
        fullLimitBytes: 1000,
        offlineReserveCount: 3,
      );
      final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
      await manager.put('a', f1, tier: CacheTier.full);

      final lease = manager.acquire('a', tier: CacheTier.full);
      expect(manager.isOfflineReserve('a', tier: CacheTier.full), isFalse);
      expect(manager.pinCountOf('a', tier: CacheTier.full), 1);

      manager.recordSuccessfullyDisplayed('a', tier: CacheTier.full);
      expect(manager.isOfflineReserve('a', tier: CacheTier.full), isTrue);
      expect(manager.pinCountOf('a', tier: CacheTier.full), 1);

      lease.release();
      expect(manager.pinCountOf('a', tier: CacheTier.full), 0);
      // Still protected by the reserve flag even though no longer pinned.
      expect(manager.isOfflineReserve('a', tier: CacheTier.full), isTrue);
    });
  });

  group('clear()', () {
    test('clear ignores pins/reserves - it is an explicit user action', () async {
      final manager = ImageCacheManager(
        thumbnailLimitBytes: 1000,
        fullLimitBytes: 1000,
      );
      final f1 = await _writeTempFile(tempDir, 'a.jpg', 100);
      await manager.put('a', f1, tier: CacheTier.full);
      manager.acquire('a', tier: CacheTier.full);
      manager.recordSuccessfullyDisplayed('a', tier: CacheTier.full);

      await manager.clear(tier: CacheTier.full);

      expect(manager.contains('a', tier: CacheTier.full), isFalse);
      expect(manager.currentSizeBytes(CacheTier.full), 0);
    });
  });
}
