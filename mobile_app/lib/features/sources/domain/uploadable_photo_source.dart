import 'dart:io';

import '../../../core/utils/result.dart';
import 'photo_folder.dart';

/// Optional capability mixed into a [PhotoSource] implementation that
/// supports uploading new images (e.g. WebDAV/Nextcloud), as opposed to
/// read-only sources (e.g. a shared/read-only SMB share, a mock source).
abstract class UploadablePhotoSource {
  /// Whether this source instance currently supports uploads (may depend on
  /// runtime state, e.g. write permission on the remote share).
  bool get canUpload;

  /// Uploads [file] to [targetFolder], or to the source's default upload
  /// location when `null`.
  Future<Result<void>> uploadImage(File file, {PhotoFolder? targetFolder});
}
