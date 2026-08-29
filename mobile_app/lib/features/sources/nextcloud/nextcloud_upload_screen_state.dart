import 'dart:async';
import 'dart:io';

import '../../../core/errors/failure.dart';
import '../../../core/utils/result.dart';
import '../domain/photo_folder.dart';
import 'nextcloud_photo_source.dart';

/// Lifecycle state of a single upload attempt.
enum UploadStatus { idle, uploading, success, failure }

/// Pure state/controller for "upload a picture into a Nextcloud source"
/// (docs/PLAN.md `nextcloud_upload_screen.dart`). Deliberately has **no
/// Flutter widget dependency** so it's testable with plain `flutter test`;
/// the real screen (built by a parallel agent/milestone) is expected to
/// construct one of these, call [pickAndUpload] or [upload] from a button
/// handler, and listen to [statusChanges] to update its UI.
///
/// Per docs/PLAN.md, a successful upload should be reflected immediately in
/// the local media index (not wait for the next crawl) and optionally
/// trigger a working-set-pool refill so the image shows up in the slideshow
/// promptly. This class exposes that as an injectable [onUploaded] callback
/// rather than depending directly on `media_index.dart`/`working_set_pool.dart`
/// (which would create a layering dependency from `sources` onto `index`).
class NextcloudUploadScreenState {
  NextcloudUploadScreenState({
    required NextcloudPhotoSource source,
    PhotoFolder? targetFolder,
    FutureOr<void> Function(File file)? onUploaded,
  })  : _source = source,
        _targetFolder = targetFolder,
        _onUploaded = onUploaded;

  final NextcloudPhotoSource _source;
  PhotoFolder? _targetFolder;
  final FutureOr<void> Function(File file)? _onUploaded;

  UploadStatus _status = UploadStatus.idle;
  Failure? _lastFailure;
  File? _lastUploadedFile;

  UploadStatus get status => _status;
  Failure? get lastFailure => _lastFailure;
  File? get lastUploadedFile => _lastUploadedFile;

  /// Whether the underlying source currently reports write access. The UI
  /// should hide/disable the upload affordance entirely when this is false,
  /// per docs/PLAN.md's "prüft schlicht `source is UploadablePhotoSource &&
  /// source.canUpload`" rule.
  bool get canUpload => _source.canUpload;

  final StreamController<UploadStatus> _statusController =
      StreamController<UploadStatus>.broadcast();

  Stream<UploadStatus> get statusChanges => _statusController.stream;

  void setTargetFolder(PhotoFolder? folder) {
    _targetFolder = folder;
  }

  void _setStatus(UploadStatus status) {
    _status = status;
    _statusController.add(status);
  }

  /// Uploads [file] to the configured Nextcloud source/folder.
  Future<Result<void>> upload(File file) async {
    if (!_source.canUpload) {
      const failure = Unsupported(
        'Upload attempted on a source without write access',
      );
      _lastFailure = failure;
      _setStatus(UploadStatus.failure);
      return Result.err(failure);
    }

    _setStatus(UploadStatus.uploading);
    final result = await _source.uploadImage(file, targetFolder: _targetFolder);
    if (result.isOk) {
      _lastUploadedFile = file;
      _lastFailure = null;
      _setStatus(UploadStatus.success);
      await _onUploaded?.call(file);
      return Result.ok(null);
    } else {
      final failure = result.failureOrNull!;
      _lastFailure = failure;
      _setStatus(UploadStatus.failure);
      return Result.err(failure);
    }
  }

  void dispose() {
    unawaited(_statusController.close());
  }
}
