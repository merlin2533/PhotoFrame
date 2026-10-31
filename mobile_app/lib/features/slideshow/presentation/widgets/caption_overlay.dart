import 'package:flutter/material.dart';

import '../../../sources/domain/photo_item.dart';

/// Small pill caption at the bottom left showing the photo's date and folder
/// name. Same pill style as `SourceLabelOverlay` (which sits bottom right).
/// Visibility is controlled by the caller via `AppSettings.showCaptionOverlay`.
///
/// Sits at `bottom: 16`, below `PathOverlay` (which uses `bottom: 64`), so
/// both can be shown at once without overlapping.
class CaptionOverlay extends StatelessWidget {
  const CaptionOverlay({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      bottom: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white)),
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
