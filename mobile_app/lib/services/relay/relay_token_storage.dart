import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists everything needed to resume a relay session across app
/// restarts: the user's JWT access/refresh token pair (from
/// `/auth/login|register|refresh`) and, separately, the paired frame's
/// device token + frame id (from `/frames` and `/frames/:id/recover`).
///
/// Kept as a thin wrapper around [FlutterSecureStorage] so both
/// [RelayApiClient] and [TokenRefreshInterceptor] share one persistence
/// implementation and can be unit tested against a fake/mocked instance
/// without touching a real platform keychain.
class RelayTokenStorage {
  RelayTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccessToken = 'relay_access_token';
  static const _kRefreshToken = 'relay_refresh_token';
  static const _kDeviceToken = 'relay_device_token';
  static const _kUserId = 'relay_user_id';
  static const _kFrameId = 'relay_frame_id';

  Future<String?> get accessToken => _storage.read(key: _kAccessToken);

  Future<String?> get refreshToken => _storage.read(key: _kRefreshToken);

  Future<String?> get deviceToken => _storage.read(key: _kDeviceToken);

  Future<String?> get userId => _storage.read(key: _kUserId);

  Future<String?> get frameId => _storage.read(key: _kFrameId);

  Future<void> saveUserSession({
    required String userId,
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kUserId, value: userId);
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
  }

  Future<void> saveDeviceSession({
    required String frameId,
    required String deviceToken,
  }) async {
    await _storage.write(key: _kFrameId, value: frameId);
    await _storage.write(key: _kDeviceToken, value: deviceToken);
  }

  Future<void> updateAccessToken(String accessToken) =>
      _storage.write(key: _kAccessToken, value: accessToken);

  Future<void> updateRefreshToken(String refreshToken) =>
      _storage.write(key: _kRefreshToken, value: refreshToken);

  Future<void> updateDeviceToken(String deviceToken) =>
      _storage.write(key: _kDeviceToken, value: deviceToken);

  Future<void> clearUserSession() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kUserId);
  }

  Future<void> clearDeviceSession() async {
    await _storage.delete(key: _kDeviceToken);
    await _storage.delete(key: _kFrameId);
  }

  Future<bool> get hasDeviceSession async => (await deviceToken) != null;

  Future<bool> get hasUserSession async => (await accessToken) != null;
}
