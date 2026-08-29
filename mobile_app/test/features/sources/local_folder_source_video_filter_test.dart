import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_folder.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/local/local_folder_source.dart';

/// Covers the P2 decision (see docs/PLAN.md and
/// `local_folder_source.dart`'s doc comment): video files are recognized
/// but filtered out exactly like GIF/RAW - counted in [unsupportedCount],
/// never surfaced as a `MediaType.video` item, since video playback is
/// explicitly out of scope for this round.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photoframe_video_filter_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> writeFile(String name) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(const [0, 1, 2, 3]);
  }

  test('video files are excluded from listImages and counted as unsupported', () async {
    await writeFile('photo.jpg');
    await writeFile('clip.mp4');
    await writeFile('clip.mov');
    await writeFile('animation.gif');

    final source = LocalFolderSource(id: 'local-1', rootPath: tempDir.path);
    addTearDown(source.dispose);

    const root = PhotoFolder(id: '', name: 'root', path: '');
    final items = await source.listImages(root).toList();
    final okItems = items.map((r) => r.valueOrNull).whereType<PhotoItem>().toList();

    expect(okItems.length, 1);
    expect(okItems.single.name, 'photo.jpg');
    expect(okItems.every((i) => i.mediaType == MediaType.image), isTrue);
    // 2 videos + 1 gif = 3 unsupported files.
    expect(source.unsupportedCount, 3);
  });

  test('a mix of video extensions is all treated as unsupported, not as MediaType.video', () async {
    for (final ext in ['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp']) {
      await writeFile('clip.$ext');
    }

    final source = LocalFolderSource(id: 'local-2', rootPath: tempDir.path);
    addTearDown(source.dispose);

    const root = PhotoFolder(id: '', name: 'root', path: '');
    final items = await source.listImages(root).toList();
    final okItems = items.map((r) => r.valueOrNull).whereType<PhotoItem>().toList();

    expect(okItems, isEmpty);
    expect(source.unsupportedCount, 7);
  });
}
