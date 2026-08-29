import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/errors/failure.dart';
import '../../core/utils/result.dart';
import 'relay_token_storage.dart';
import 'token_refresh_interceptor.dart';

/// --- Wire-level DTOs -------------------------------------------------
///
/// These mirror the relay server's JSON response shapes as closely as
/// possible (see relay_server/src/routes/*.ts) rather than any client-side
/// domain concept - [RelayPairingRepository] (features/pairing) is the
/// layer that turns these into app-facing domain models.

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.username,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String username;
  final String accessToken;
  final String refreshToken;
}

class FrameRegistration {
  const FrameRegistration({required this.frameId, required this.deviceToken});

  final String frameId;
  final String deviceToken;
}

class FrameRecovery {
  const FrameRecovery({
    required this.frameId,
    required this.deviceToken,
    required this.fingerprint,
  });

  final String frameId;
  final String deviceToken;

  /// Fingerprint of the freshly-rotated public key, per
  /// relay_server/src/auth/recovery.ts. `null` either because the server
  /// build in use hasn't wired this field into the HTTP response yet, or
  /// because the recovered frame genuinely has no public key yet - both
  /// cases must be handled the same way client-side: nothing to re-share
  /// out-of-band yet.
  final String? fingerprint;
}

class PairingCreated {
  const PairingCreated({
    required this.pairingId,
    required this.code,
    required this.expiresAt,
    required this.fingerprint,
    this.fingerprintReason,
  });

  final String pairingId;
  final String code;
  final DateTime expiresAt;

  /// TOFU fingerprint of the creating frame's current public key (Crockford
  /// Base32, 8 chars), meant to travel out-of-band via the pairing
  /// QR/deep-link. `null` when the creating frame has no public_key yet -
  /// see [fingerprintReason].
  final String? fingerprint;
  final String? fingerprintReason;
}

class PairingMemberInfo {
  const PairingMemberInfo({
    required this.frameId,
    required this.role,
    required this.joinedAt,
    required this.keyFingerprint,
  });

  final String frameId;
  final String role;
  final DateTime joinedAt;

  /// The member frame's CURRENT key fingerprint as seen by the server right
  /// now - this is what must be compared against the fingerprint the local
  /// client previously trusted for this frameId (see
  /// features/pairing/domain/key_fingerprint.dart). `null` if that frame
  /// has no public_key yet.
  final String? keyFingerprint;

  bool get isOwner => role == 'owner';
}

class PairingDetails {
  const PairingDetails({
    required this.pairingId,
    required this.name,
    required this.members,
  });

  final String pairingId;
  final String name;
  final List<PairingMemberInfo> members;
}

class ConfigPushMessage {
  const ConfigPushMessage({
    required this.id,
    required this.senderFrameId,
    required this.ciphertext,
    required this.createdAt,
  });

  final String id;
  final String senderFrameId;

  /// Opaque, end-to-end-encrypted payload - the relay (and this client
  /// layer) never interprets it. Decryption happens above this layer, once
  /// the receiving frame has verified the sender's fingerprint (TOFU).
  final String ciphertext;
  final DateTime createdAt;
}

class UploadedImage {
  const UploadedImage({
    required this.imageId,
    required this.deduped,
    this.contentHash,
    this.width,
    this.height,
  });

  final String imageId;

  /// True if this upload was recognized as a retry of a previous upload
  /// (same `clientUploadId`) and no new blob was written.
  final bool deduped;
  final String? contentHash;
  final int? width;
  final int? height;
}

class RemoteImage {
  const RemoteImage({
    required this.id,
    required this.uploadedByFrameId,
    required this.uploadedAt,
    required this.contentHash,
    this.width,
    this.height,
  });

  final String id;
  final String uploadedByFrameId;
  final DateTime uploadedAt;
  final String contentHash;
  final int? width;
  final int? height;
}

/// Thin, mockable Dio-based REST client for the relay server's
/// `/api/v1/*` surface (relay_server/src/routes/*.ts).
///
/// Every call is wrapped to return `Result<T>` (see core/utils/result.dart)
/// instead of throwing, mapping HTTP/transport failures onto the shared
/// [Failure] taxonomy so callers never need to know about Dio directly.
///
/// This class only speaks HTTP; it has no opinion on TOFU, pairing
/// business rules, or UI. Kept behind no interface of its own (unlike
/// `PairingRepository`) because it is meant to be the single, concrete
/// implementation of "how to talk to a relay server" - tests substitute a
/// custom `Dio` (via the `dio` constructor parameter, e.g. with
/// `DioAdapter` from `http_mock_adapter` or a hand-rolled
/// `HttpClientAdapter`) rather than mocking this class itself.
class RelayApiClient {
  RelayApiClient({
    required String baseUrl,
    required this.tokenStorage,
    Dio? dio,
  })  : baseUrl = _stripTrailingSlash(baseUrl),
        dioClient = dio ??
            Dio(BaseOptions(
              baseUrl: '${_stripTrailingSlash(baseUrl)}/api/v1',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            )) {
    dioClient.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) async {
        // Attach whichever bearer token is appropriate. Endpoints under
        // /auth don't need one; everything else prefers the device token
        // (frame identity) except /frames itself, which is user-scoped.
        final path = options.path;
        if (path.startsWith('/auth')) {
          handler.next(options);
          return;
        }
        final isUserScoped = path.startsWith('/frames');
        final token = isUserScoped ? await tokenStorage.accessToken : await tokenStorage.deviceToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      }),
    );
    dioClient.interceptors.add(
      TokenRefreshInterceptor(tokenStorage: tokenStorage, baseUrl: this.baseUrl),
    );
  }

  /// Relay server origin, e.g. `https://relay.example.com` (no trailing
  /// slash, no `/api/v1` suffix - that's added internally).
  final String baseUrl;
  final RelayTokenStorage tokenStorage;
  final Dio dioClient;

  static String _stripTrailingSlash(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  Future<Result<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Result.ok(await body());
    } on DioException catch (e) {
      return Result.err(_mapDioError(e));
    } on SocketException catch (e) {
      return Result.err(NetworkError('No connection to relay server', cause: e));
    } catch (e) {
      return Result.err(NetworkError('Unexpected relay client error', cause: e));
    }
  }

  Failure _mapDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return Timeout('Relay request timed out', cause: e);
    }
    if (e.type == DioExceptionType.connectionError) {
      return NetworkError('Could not reach relay server', cause: e);
    }

    final status = e.response?.statusCode;
    final serverMessage = _extractServerError(e.response?.data);
    switch (status) {
      case 401:
        return AuthError(serverMessage ?? 'Not authenticated', cause: e);
      case 403:
        return PermissionDenied(serverMessage ?? 'Not permitted', cause: e);
      case 404:
        return NotFound(serverMessage ?? 'Not found', cause: e);
      case 409:
        return AuthError(serverMessage ?? 'Conflict', cause: e);
      case 410:
        return NotFound(serverMessage ?? 'Gone', cause: e);
      case 413:
        return QuotaExceeded(serverMessage ?? 'Quota exceeded', cause: e);
      case 429:
        return NetworkError(serverMessage ?? 'Rate limited, try again later', cause: e);
      default:
        return NetworkError(serverMessage ?? 'Relay request failed', cause: e);
    }
  }

  String? _extractServerError(Object? data) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    return null;
  }

  // --- Auth (user account, JWT) ---------------------------------------

  Future<Result<AuthSession>> register({
    required String username,
    required String password,
    String? inviteCode,
  }) {
    return _guard(() async {
      final response = await dioClient.post<Map<String, dynamic>>('/auth/register', data: {
        'username': username,
        'password': password,
        if (inviteCode != null) 'inviteCode': inviteCode,
      });
      final data = response.data!;
      final session = AuthSession(
        userId: data['userId'] as String,
        username: data['username'] as String,
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      await tokenStorage.saveUserSession(
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      return session;
    });
  }

  Future<Result<AuthSession>> login({required String username, required String password}) {
    return _guard(() async {
      final response = await dioClient.post<Map<String, dynamic>>('/auth/login', data: {
        'username': username,
        'password': password,
      });
      final data = response.data!;
      final session = AuthSession(
        userId: data['userId'] as String,
        username: data['username'] as String,
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      await tokenStorage.saveUserSession(
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      return session;
    });
  }

  // --- Frames (device identity) ---------------------------------------

  Future<Result<FrameRegistration>> registerFrame({
    required String displayName,
    required String publicKey,
  }) {
    return _guard(() async {
      final response = await dioClient.post<Map<String, dynamic>>('/frames', data: {
        'displayName': displayName,
        'publicKey': publicKey,
      });
      final data = response.data!;
      final registration = FrameRegistration(
        frameId: data['frameId'] as String,
        deviceToken: data['deviceToken'] as String,
      );
      await tokenStorage.saveDeviceSession(
        frameId: registration.frameId,
        deviceToken: registration.deviceToken,
      );
      return registration;
    });
  }

  Future<Result<FrameRecovery>> recoverFrame({
    required String frameId,
    required String newPublicKey,
  }) {
    return _guard(() async {
      final response = await dioClient.post<Map<String, dynamic>>('/frames/$frameId/recover', data: {
        'newPublicKey': newPublicKey,
      });
      final data = response.data!;
      final recovery = FrameRecovery(
        frameId: data['frameId'] as String,
        deviceToken: data['deviceToken'] as String,
        // Tolerate a server build that hasn't added `fp` to this response
        // yet (see Blocker 2 handoff note) - absence must never be
        // mistaken for an authenticated "no key" fingerprint of null.
        fingerprint: data.containsKey('fp') ? data['fp'] as String? : null,
      );
      await tokenStorage.saveDeviceSession(
        frameId: recovery.frameId,
        deviceToken: recovery.deviceToken,
      );
      return recovery;
    });
  }

  // --- Pairing ----------------------------------------------------------

  Future<Result<PairingCreated>> createPairingCode({String? pairingName, String? pairingId}) {
    return _guard(() async {
      final response = await dioClient.post<Map<String, dynamic>>('/pairing/create-code', data: {
        if (pairingName != null) 'pairingName': pairingName,
        if (pairingId != null) 'pairingId': pairingId,
      });
      final data = response.data!;
      return PairingCreated(
        pairingId: data['pairingId'] as String,
        code: data['code'] as String,
        expiresAt: DateTime.parse(data['expiresAt'] as String),
        fingerprint: data['fp'] as String?,
        fingerprintReason: data['fpReason'] as String?,
      );
    });
  }

  Future<Result<String>> redeemPairingCode(String code) {
    return _guard(() async {
      final response = await dioClient.post<Map<String, dynamic>>('/pairing/redeem', data: {'code': code});
      return response.data!['pairingId'] as String;
    });
  }

  Future<Result<PairingDetails>> getPairing(String pairingId) {
    return _guard(() async {
      final response = await dioClient.get<Map<String, dynamic>>('/pairing/$pairingId');
      final data = response.data!;
      final pairing = data['pairing'] as Map<String, dynamic>;
      final members = (data['members'] as List)
          .cast<Map<String, dynamic>>()
          .map((m) => PairingMemberInfo(
                frameId: m['frameId'] as String,
                role: m['role'] as String,
                joinedAt: DateTime.parse(m['joinedAt'] as String),
                keyFingerprint: m['keyFingerprint'] as String?,
              ))
          .toList();
      return PairingDetails(
        pairingId: pairing['id'] as String,
        name: pairing['name'] as String,
        members: members,
      );
    });
  }

  Future<Result<void>> renamePairing(String pairingId, String name) {
    return _guard(() async {
      await dioClient.patch<void>('/pairing/$pairingId', data: {'name': name});
    });
  }

  Future<Result<void>> leavePairing(String pairingId) {
    return _guard(() async {
      await dioClient.post<void>('/pairing/$pairingId/leave');
    });
  }

  /// Owner-only: removes another member from the pairing.
  Future<Result<void>> removeMember(String pairingId, String frameId) {
    return _guard(() async {
      await dioClient.delete<void>('/pairing/$pairingId/members/$frameId');
    });
  }

  /// Owner-only: deletes the whole pairing.
  Future<Result<void>> deletePairing(String pairingId) {
    return _guard(() async {
      await dioClient.delete<void>('/pairing/$pairingId');
    });
  }

  // --- Config push (end-to-end encrypted, opaque to the relay) ---------

  Future<Result<String>> sendConfigPush({required String targetFrameId, required String ciphertext}) {
    return _guard(() async {
      final response = await dioClient.post<Map<String, dynamic>>('/config-push', data: {
        'targetFrameId': targetFrameId,
        'ciphertext': ciphertext,
      });
      return response.data!['id'] as String;
    });
  }

  Future<Result<List<ConfigPushMessage>>> pendingConfigPushes() {
    return _guard(() async {
      final response = await dioClient.get<Map<String, dynamic>>('/config-push/pending');
      final pushes = (response.data!['pushes'] as List).cast<Map<String, dynamic>>();
      return pushes
          .map((p) => ConfigPushMessage(
                id: p['id'] as String,
                senderFrameId: p['sender_frame_id'] as String,
                ciphertext: p['ciphertext'] as String,
                createdAt: DateTime.parse(p['created_at'] as String),
              ))
          .toList();
    });
  }

  Future<Result<void>> ackConfigPush(String pushId) {
    return _guard(() async {
      await dioClient.post<void>('/config-push/$pushId/ack');
    });
  }

  // --- Images (shared album) --------------------------------------------

  Future<Result<UploadedImage>> uploadImage({
    required String pairingId,
    required String clientUploadId,
    required File file,
  }) {
    return _guard(() async {
      final formData = FormData.fromMap({
        'pairingId': pairingId,
        'clientUploadId': clientUploadId,
        'file': await MultipartFile.fromFile(file.path),
      });
      final response = await dioClient.post<Map<String, dynamic>>('/images', data: formData);
      final data = response.data!;
      return UploadedImage(
        imageId: data['imageId'] as String,
        deduped: data['deduped'] == true,
        contentHash: data['contentHash'] as String?,
        width: data['width'] as int?,
        height: data['height'] as int?,
      );
    });
  }

  Future<Result<List<RemoteImage>>> listImages(String pairingId) {
    return _guard(() async {
      final response = await dioClient.get<Map<String, dynamic>>('/images/pairing/$pairingId');
      final images = (response.data!['images'] as List).cast<Map<String, dynamic>>();
      return images
          .map((i) => RemoteImage(
                id: i['id'] as String,
                uploadedByFrameId: i['uploaded_by_frame_id'] as String,
                uploadedAt: DateTime.parse(i['uploaded_at'] as String),
                contentHash: i['content_hash'] as String,
                width: i['width'] as int?,
                height: i['height'] as int?,
              ))
          .toList();
    });
  }

  Future<Result<void>> hideImage(String imageId) {
    return _guard(() async {
      await dioClient.post<void>('/images/$imageId/hide');
    });
  }

  Future<Result<void>> unhideImage(String imageId) {
    return _guard(() async {
      await dioClient.post<void>('/images/$imageId/unhide');
    });
  }

  Future<Result<void>> deleteImage(String imageId) {
    return _guard(() async {
      await dioClient.delete<void>('/images/$imageId');
    });
  }

  Future<Result<File>> downloadImageToFile({
    required String imageId,
    required String destinationPath,
    bool thumbnail = false,
  }) {
    return _guard(() async {
      await dioClient.download(
        '/images/$imageId/file${thumbnail ? '?variant=thumb' : ''}',
        destinationPath,
      );
      return File(destinationPath);
    });
  }

  /// Convenience for [RelaySocketClient]: the base HTTP origin (no path),
  /// since socket.io connects to the origin directly rather than under
  /// `/api/v1`.
  String get socketOrigin => baseUrl;
}
