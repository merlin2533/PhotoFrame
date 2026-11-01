import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/caption_overlay.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';

PhotoItem _item({required String id, DateTime? takenAt}) => PhotoItem(
      id: id,
      sourceId: 'src-1',
      folderId: 'f',
      name: id.split('/').last,
      mediaType: MediaType.image,
      size: 1,
      mtime: DateTime(2020, 1, 2),
      takenAt: takenAt,
    );

void main() {
  group('captionTextFor', () {
    test('shows taken date and folder name', () {
      final item = _item(
        id: '2024/Summer/IMG_0001.jpg',
        takenAt: DateTime(2024, 7, 4),
      );
      expect(captionTextFor(item), '04.07.2024  ·  Summer');
    });

    test('falls back to mtime when takenAt is unknown', () {
      final item = _item(id: 'Trip/a.jpg');
      expect(captionTextFor(item), '02.01.2020  ·  Trip');
    });

    test('shows date only for a file at the source root', () {
      final item = _item(id: 'IMG_0002.jpg', takenAt: DateTime(2023, 12, 24));
      expect(captionTextFor(item), '24.12.2023');
    });
  });

  testWidgets('CaptionOverlay renders its text', (tester) async {
    final item = _item(id: 'Urlaub/a.jpg', takenAt: DateTime(2022, 8, 9));
    await tester.pumpWidget(MaterialApp(
      home: Stack(
        children: [CaptionOverlay(text: captionTextFor(item))],
      ),
    ));
    expect(find.text('09.08.2022  ·  Urlaub'), findsOneWidget);
  });
}
