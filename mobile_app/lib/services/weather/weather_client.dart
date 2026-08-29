import 'package:dio/dio.dart';

import 'weather_models.dart';

/// Thin client for the free, keyless Open-Meteo APIs:
/// - `https://api.open-meteo.com/v1/forecast` for current conditions.
/// - `https://geocoding-api.open-meteo.com/v1/search` for city-name lookup.
///
/// Uses `dio` (already the project's HTTP client of choice, see
/// `services/relay/relay_api_client.dart`) rather than adding the `http`
/// package. A [Dio] instance can be injected for testing (see
/// `test/services/weather/weather_client_test.dart`, which swaps in a fake
/// [HttpClientAdapter] - no real network calls are made in tests).
///
/// Caches the last reading per (rounded) coordinate in memory so that
/// re-rendering the slideshow overlay on every image change does not refetch
/// on every call - callers should still call [fetchCurrentWeather]
/// liberally (e.g. once per displayed image) and rely on this cache rather
/// than building their own timer-based fetch logic, though
/// `WeatherOverlay` additionally throttles its own polling (see that
/// widget's doc comment).
class WeatherClient {
  WeatherClient({
    Dio? dio,
    this.cacheDuration = const Duration(minutes: 45),
    DateTime Function()? now,
  })  : _dio = dio ?? Dio(),
        _now = now ?? DateTime.now;

  static const String forecastBaseUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String geocodingBaseUrl = 'https://geocoding-api.open-meteo.com/v1/search';

  final Dio _dio;

  /// How long a cached reading for a given location is considered fresh
  /// before [fetchCurrentWeather] issues a new request. Open-Meteo's own
  /// current-weather data updates roughly hourly, so 30-60 min is a
  /// reasonable default; picked 45 as the midpoint.
  final Duration cacheDuration;

  final DateTime Function() _now;

  final Map<String, CurrentWeather> _cache = {};

  static String _cacheKey(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}';

  /// Fetches current temperature + WMO weather code for [latitude]/[longitude].
  ///
  /// Returns a cached reading (see [cacheDuration]) unless [forceRefresh] is
  /// set or no cached value exists yet for this (rounded) coordinate.
  Future<CurrentWeather> fetchCurrentWeather({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey(latitude, longitude);
    final cached = _cache[key];
    if (!forceRefresh && cached != null) {
      final age = _now().difference(cached.fetchedAt);
      if (age < cacheDuration) return cached;
    }

    final response = await _dio.get<Map<String, dynamic>>(
      forecastBaseUrl,
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'current_weather': true,
      },
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Empty response body from Open-Meteo forecast API');
    }
    final weather = CurrentWeather.fromForecastResponseJson(data, fetchedAt: _now());
    _cache[key] = weather;
    return weather;
  }

  /// Looks up candidate locations for a free-text city name via Open-Meteo's
  /// geocoding API. Returns an empty list for a blank query rather than
  /// hitting the network.
  Future<List<GeocodingResult>> searchLocations(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final response = await _dio.get<Map<String, dynamic>>(
      geocodingBaseUrl,
      queryParameters: {
        'name': trimmed,
        'count': 10,
        'language': 'de',
        'format': 'json',
      },
    );
    final data = response.data;
    final results = data?['results'] as List<dynamic>?;
    if (results == null) return const [];
    return results
        .map((r) => GeocodingResult.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Drops all cached readings. Exposed mainly for tests; production
  /// callers normally just wait out [cacheDuration] or pass [forceRefresh].
  void clearCache() => _cache.clear();
}
