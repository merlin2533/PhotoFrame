import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/result.dart';
import '../../../services/relay/relay_api_client.dart';
import '../domain/media_type.dart';
import '../domain/photo_folder.dart';
import '../domain/photo_item.dart';
import '../domain/photo_source.dart';
import '../domain/uploadable_photo_source.dart';

/// [PhotoSource] backed by a relay-server "shared album" (one pairing's
/// uploaded images, see relay_server/src/routes/images.ts). Also
/// implements [UploadablePhotoSource] since, unlike SMB/local sources, a
/// shared album is meant to be written to directly from the app (the
/// "Upload"/"family album" use case in docs/PLAN.md).
///
/// Modeling note: a shared album has no real folder hierarchy server-side
/// (`GET /images/pairing/:id` returns a flat, newest-first list) - this
/// class exposes exactly one synthetic root [PhotoFolder] whose id is the
/// pairing id, so it still satisfies [PhotoSource.listFolders]/
/// [PhotoSource.listImages] without pretending to support subfolders it
/// doesn't have.
class SharedAlbumPhotoSource implements PhotoSource, UploadablePhotoSource {
  SharedAlbumPhotoSource({
    required this.id,
    required this.displayName,
    required String pairingId,
    required RelayApiClient apiClient,
    Directory? cacheDirectory,
    Uuid? uuid,
  })  : _pairingId = pairingId,
        _api = apiClient,
        _cacheDirectory = cacheDirectory,
        _uuid = uuid ?? const Uuid();

  @override
  final String id;

  @override
  final String displayName;

  @override
  SourceType get type => SourceType.sharedAlbum;

  final String _pairingId;
  final RelayApiClient _api;
  final Directory? _cacheDirectory;
  final Uuid _uuid;

  PhotoFolder get _rootFolder => PhotoFolder(id: _pairingId, name: displayName, path: '/');

  @override
  Future<Result<ConnectionStatus>> testConnection({Duration timeout = const Duration(seconds: 8)}) async {
    final stopwatch = Stopwatch()..start();
    final result = await _api.getPairing(_pairingId);
    stopwatch.stop();
    return result.fold(
      (pairing) => Result.ok(ConnectionStatus(
        reachable: true,
        latency: stopwatch.elapsed,
        detail: 'shared album "${pairing.name}" (${pairing.members.length} members)',
      )),
      (failure) => Result.ok(ConnectionStatus(reachable: false, detail: failure.message)),
    );
  }

  @override
  Stream<Result<PhotoFolder>> listFolders({PhotoFolder? parent, CancellationToken? token}) async* {
    if (parent != null) return; // flat structure - see class doc comment.
    token?.throwIfCancelled();
    yield Result.ok(_rootFolder);
  }

  @override
  Stream<Result<PhotoItem>> listImages(PhotoFolder folder, {bool recursive = true, CancellationToken? token}) async* {
    if (folder.id != _pairingId) {
      yield Result.err(NotFound('Unknown shared-album folder: ${folder.id}'));
      return;
    }

    final result = await _api.listImages(_pairingId);
    token?.throwIfCancelled();

    if (result.isErr) {
      yield Result.err(result.failureOrNull!);
      return;
    }

    for (final image in result.valueOrNull!) {
      token?.throwIfCancelled();
      yield Result.ok(PhotoItem(
        id: image.id,
        sourceId: id,
        folderId: _pairingId,
        name: '${image.id}.jpg',
        mediaType: MediaType.image,
        width: image.width,
        height: image.height,
        // The relay doesn't report EXIF capture time for shared-album
        // images (it strips EXIF on ingest) - upload time is the closest
        // available signal and is used consistently for sort/dedupe here.
        takenAt: image.uploadedAt,
        size: 0, // not reported by GET /images/pairing/:id - unknown until fetched.
        mtime: image.uploadedAt,
      ));
    }
  }

  @override
  Future<Result<File>> fetchToCache(PhotoItem item, {CancellationToken? token}) async {
    token?.throwIfCancelled();
    try {
      final dir = _cacheDirectory ?? await getTemporaryDirectory();
      final destination = File('${dir.path}${Platform.pathSeparator}shared_${item.id}.jpg');
      if (await destination.exists()) {
        return Result.ok(destination);
      }
      return _api.downloadImageToFile(imageId: item.id, destinationPath: destination.path);
    } catch (e) {
      return Result.err(NetworkError('Failed to prepare cache destination', cause: e));
    }
  }

  /// The relay's realtime channel only pushes `config_push` notifications
  /// (see relay_server/src/realtime/socket.ts) - there is no "new image
  /// uploaded" event today. Until that exists server-side, this stays
  /// empty and callers must poll [listImages] periodically, exactly like
  /// the other, genuinely push-less sources (SMB/local/SAF).
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> dispose() async {}

  // --- UploadablePhotoSource --------------------------------------------

  @override
  bool get canUpload => true;

  @override
  Future<Result<void>> uploadImage(File file, {PhotoFolder? targetFolder}) async {
    final clientUploadId = _uuid.v4();
    final result = await _api.uploadImage(
      pairingId: targetFolder?.id ?? _pairingId,
      clientUploadId: clientUploadId,
      file: file,
    );
    return result.map((_) {});
  }
}
