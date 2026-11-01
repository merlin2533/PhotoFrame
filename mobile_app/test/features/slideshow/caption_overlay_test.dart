import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/caption_overlay.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/overlay_text_panel.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/source_label_overlay.dart';
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

  testWidgets('CaptionOverlay text sits on a dark panel and is readable',
      (tester) async {
    const text = '09.08.2022  \u00b7  Urlaub';
    await tester.pumpWidget(const MaterialApp(
      home: Stack(
        children: [CaptionOverlay(text: text)],
      ),
    ));

    final label = find.text(text);
    expect(label, findsOneWidget);
    final panel =
        find.ancestor(of: label, matching: find.byType(OverlayTextPanel));
    expect(panel, findsOneWidget);

    final container = tester.widget<Container>(
      find.descendant(of: panel, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, OverlayTextPanel.backgroundColor);
    expect(decoration.color!.a, greaterThanOrEqualTo(0.6));
    expect(decoration.borderRadius, isNotNull);

    final style = tester.widget<Text>(label).style!;
    expect(style.color, Colors.white);
    expect(style.fontSize, greaterThanOrEqualTo(16));
  });

  testWidgets('SourceLabelOverlay text sits on the same dark panel',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Stack(
        children: [SourceLabelOverlay(label: 'Nextcloud')],
      ),
    ));

    final label = find.text('Nextcloud');
    expect(label, findsOneWidget);
    final panel =
        find.ancestor(of: label, matching: find.byType(OverlayTextPanel));
    expect(panel, findsOneWidget);
    final style = tester.widget<Text>(label).style!;
    expect(style.color, Colors.white);
    expect(style.fontSize, greaterThanOrEqualTo(16));
  });
}
