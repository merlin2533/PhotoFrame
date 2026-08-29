import 'package:dio/dio.dart';

import 'relay_token_storage.dart';

/// Dio interceptor that transparently recovers from an expired user access
/// token by calling `POST /api/v1/auth/refresh` and retrying the original
/// request once with the new token.
///
/// Only applies to user-JWT-authenticated calls (`Authorization: Bearer
/// <accessToken>`); device-token calls (frame-authenticated, e.g. pairing,
/// images, config-push) 401 on revocation/loss and are surfaced as-is - a
/// device token has no refresh flow server-side, the only recovery path is
/// `/frames/:id/recover`, which is a deliberate user action, not something
/// this interceptor should trigger silently.
///
/// Concurrency note: several requests can 401 around the same moment (e.g.
/// a burst of calls right as the access token expires). Only the first
/// triggers an actual `/auth/refresh` call; concurrent callers await the
/// same in-flight [Future] so we never fire overlapping refreshes - the
/// refresh endpoint rotates (invalidates) the refresh token on each use, so
/// a second parallel call would otherwise fail because the first already
/// consumed it.
class TokenRefreshInterceptor extends Interceptor {
  TokenRefreshInterceptor({
    required this.tokenStorage,
    required this.baseUrl,
    Dio? refreshDio,
  }) : refreshDio = refreshDio ?? Dio(BaseOptions(baseUrl: baseUrl));

  final RelayTokenStorage tokenStorage;
  final String baseUrl;

  /// A bare Dio instance with no interceptors attached, used only for the
  /// refresh call itself. Reusing the main client (which carries this very
  /// interceptor) would risk recursing back into [onError] if the refresh
  /// call itself ever 401s.
  final Dio refreshDio;

  Future<String?>? _refreshInFlight;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _handle(err, handler);
  }

  Future<void> _handle(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final isAuthEndpoint = err.requestOptions.path.contains('/auth/');
    final hadBearerToken =
        (err.requestOptions.headers['Authorization'] as String?)?.startsWith('Bearer ') ?? false;

    if (statusCode != 401 || isAuthEndpoint || !hadBearerToken) {
      handler.next(err);
      return;
    }

    final newAccessToken = await _refresh();
    if (newAccessToken == null) {
      handler.next(err);
      return;
    }

    try {
      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
      final response = await refreshDio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await tokenStorage.refreshToken;
    if (refreshToken == null) return null;

    try {
      final response = await refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data;
      final newAccessToken = data?['accessToken'] as String?;
      final newRefreshToken = data?['refreshToken'] as String?;
      if (newAccessToken == null) return null;

      await tokenStorage.updateAccessToken(newAccessToken);
      if (newRefreshToken != null) {
        await tokenStorage.updateRefreshToken(newRefreshToken);
      }
      return newAccessToken;
    } on DioException {
      return null;
    }
  }
}
