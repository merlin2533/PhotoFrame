import 'package:flutter/material.dart';

import '../../../sources/domain/photo_item.dart';
import 'overlay_text_panel.dart';

/// Caption panel at the bottom left showing the photo's date and folder
/// name. Same panel style as `SourceLabelOverlay` (which sits bottom right).
/// Visibility is controlled by the caller via `AppSettings.showCaptionOverlay`.
///
/// Sits at `bottom: 16`. When the clock or weather pill occupies that corner,
/// [raised] lifts the caption above it (`bottom: 64`).
class CaptionOverlay extends StatelessWidget {
  const CaptionOverlay({super.key, required this.text, this.raised = false});

  final String text;

  /// Place the caption above the bottom-left clock/weather pill.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      bottom: raised ? 64 : 16,
      child: IgnorePointer(
        child: OverlayTextPanel(
          child: Text(text, style: overlayTextStyle),
        ),
      ),
    );
  }
}

/// Caption text for [item]: `dd.MM.yyyy` of the taken date (falls back to the
/// file's mtime), followed by the containing folder name when there is one.
String captionTextFor(PhotoItem item) {
  final text = formatCaptionDate(item.takenAt ?? item.mtime);
  final folder = captionFolderName(item.id);
  return folder == null ? text : '$text  ·  $folder';
}

/// `dd.MM.yyyy`, e.g. `05.03.2024`.
String formatCaptionDate(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}';
}

/// Last directory segment of a source-relative path such as
/// `2024/Summer/IMG_0001.jpg` (gives `Summer`). Returns `null` for a file
/// that sits at the source root, where there is no folder name to show.
String? captionFolderName(String relativePath) {
  final slash = relativePath.lastIndexOf('/');
  if (slash <= 0) return null;
  final dir = relativePath.substring(0, slash);
  final parent = dir.lastIndexOf('/');
  final name = parent < 0 ? dir : dir.substring(parent + 1);
  return name.isEmpty ? null : name;
}
