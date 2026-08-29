import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mobile_app/services/weather/weather_client.dart';
import 'package:mobile_app/services/weather/weather_models.dart';
import 'package:test/test.dart';

/// Hand-written [HttpClientAdapter] serving canned JSON responses keyed by
/// "METHOD path", mirroring the pattern already used in
/// `test/services/relay/relay_api_client_test.dart` - no real network calls
/// are made.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _CannedResponse> responses = {};
  int callCount = 0;

  void when(String method, String path, {required int statusCode, required Object body}) {
    responses['$method $path'] = _CannedResponse(statusCode, body);
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    final key = '${options.method} ${options.path}';
    final canned = responses[key];
    if (canned == null) {
      throw StateError('No canned response registered for $key');
    }
    return ResponseBody.fromString(
      jsonEncode(canned.body),
      canned.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _CannedResponse {
  _CannedResponse(this.statusCode, this.body);
  final int statusCode;
  final Object body;
}

Map<String, dynamic> _forecastBody({double temperature = 21.3, int weatherCode = 3}) => {
      'latitude': 52.5,
      'longitude': 13.4,
      'current_weather': {
        'temperature': temperature,
        'windspeed': 5.0,
        'winddirection': 180,
        'weathercode': weatherCode,
        'time': '2026-08-29T12:00',
      },
    };

void main() {
  group('weatherIconForWmoCode', () {
    final table = <int, WeatherIconKind>{
      0: WeatherIconKind.sunny,
      1: WeatherIconKind.partlyCloudy,
      2: WeatherIconKind.partlyCloudy,
      3: WeatherIconKind.cloudy,
      45: WeatherIconKind.fog,
      48: WeatherIconKind.fog,
      51: WeatherIconKind.drizzle,
      56: WeatherIconKind.drizzle,
      61: WeatherIconKind.rain,
      67: WeatherIconKind.rain,
      80: WeatherIconKind.rain,
      82: WeatherIconKind.rain,
      71: WeatherIconKind.snow,
      77: WeatherIconKind.snow,
      85: WeatherIconKind.snow,
      86: WeatherIconKind.snow,
      95: WeatherIconKind.thunderstorm,
      99: WeatherIconKind.thunderstorm,
      1000: WeatherIconKind.unknown,
    };

    table.forEach((code, expected) {
      test('maps WMO code $code to $expected', () {
        expect(weatherIconForWmoCode(code), expected);
      });
    });
  });

  group('CurrentWeather JSON parsing', () {
    test('parses a full forecast response', () {
      final fetchedAt = DateTime(2026, 8, 29, 12, 5);
      final weather = CurrentWeather.fromForecastResponseJson(
        _forecastBody(temperature: 18.7, weatherCode: 61),
        fetchedAt: fetchedAt,
      );
      expect(weather.temperatureC, 18.7);
      expect(weather.weatherCode, 61);
      expect(weather.icon, WeatherIconKind.rain);
      expect(weather.observedAt, DateTime.parse('2026-08-29T12:00'));
      expect(weather.fetchedAt, fetchedAt);
    });

    test('throws FormatException when current_weather is missing', () {
      expect(
        () => CurrentWeather.fromForecastResponseJson({}, fetchedAt: DateTime.now()),
        throwsFormatException,
      );
    });

    test('falls back to fetchedAt when the time field is unparsable', () {
      final fetchedAt = DateTime(2026, 1, 1);
      final json = _forecastBody()['current_weather'] as Map<String, dynamic>;
      json['time'] = 'not-a-date';
      final weather = CurrentWeather.fromCurrentWeatherJson(json, fetchedAt: fetchedAt);
      expect(weather.observedAt, fetchedAt);
    });
  });

  group('GeocodingResult', () {
    test('parses and builds a display label from name/admin1/country', () {
      final result = GeocodingResult.fromJson({
        'name': 'Berlin',
        'latitude': 52.52,
        'longitude': 13.405,
        'admin1': 'Berlin',
        'country': 'Deutschland',
      });
      expect(result.latitude, 52.52);
      expect(result.displayLabel, 'Berlin, Berlin, Deutschland');
    });

    test('omits missing admin1/country from the label', () {
      final result = GeocodingResult.fromJson({
        'name': 'Nowhere',
        'latitude': 0.0,
        'longitude': 0.0,
      });
      expect(result.displayLabel, 'Nowhere');
    });
  });

  group('WeatherClient', () {
    late _FakeAdapter adapter;
    late WeatherClient client;
    late DateTime fakeNow;

    setUp(() {
      adapter = _FakeAdapter();
      fakeNow = DateTime(2026, 8, 29, 10, 0);
      final dio = Dio()..httpClientAdapter = adapter;
      client = WeatherClient(dio: dio, now: () => fakeNow);
    });

    test('fetchCurrentWeather parses a successful response', () async {
      adapter.when('GET', WeatherClient.forecastBaseUrl, statusCode: 200, body: _forecastBody());
      final weather = await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4);
      expect(weather.temperatureC, 21.3);
      expect(weather.icon, WeatherIconKind.cloudy);
      expect(adapter.callCount, 1);
    });

    test('caches within cacheDuration - does not refetch on the second call', () async {
      adapter.when('GET', WeatherClient.forecastBaseUrl, statusCode: 200, body: _forecastBody());
      await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4);
      fakeNow = fakeNow.add(const Duration(minutes: 10));
      await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4);
      expect(adapter.callCount, 1, reason: 'second call within cacheDuration should hit the cache');
    });

    test('refetches once the cache has expired', () async {
      adapter.when('GET', WeatherClient.forecastBaseUrl, statusCode: 200, body: _forecastBody());
      await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4);
      fakeNow = fakeNow.add(const Duration(minutes: 46));
      await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4);
      expect(adapter.callCount, 2);
    });

    test('forceRefresh bypasses a still-fresh cache', () async {
      adapter.when('GET', WeatherClient.forecastBaseUrl, statusCode: 200, body: _forecastBody());
      await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4);
      await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4, forceRefresh: true);
      expect(adapter.callCount, 2);
    });

    test('caches independently per rounded coordinate', () async {
      adapter.when('GET', WeatherClient.forecastBaseUrl, statusCode: 200, body: _forecastBody());
      await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4);
      await client.fetchCurrentWeather(latitude: 40.0, longitude: -74.0);
      expect(adapter.callCount, 2);
    });

    test('searchLocations returns an empty list for a blank query without hitting the network', () async {
      final results = await client.searchLocations('   ');
      expect(results, isEmpty);
      expect(adapter.callCount, 0);
    });

    test('searchLocations parses geocoding results', () async {
      adapter.when(
        'GET',
        WeatherClient.geocodingBaseUrl,
        statusCode: 200,
        body: {
          'results': [
            {
              'name': 'Berlin',
              'latitude': 52.52,
              'longitude': 13.405,
              'admin1': 'Berlin',
              'country': 'Deutschland',
            },
            {
              'name': 'Berlin',
              'latitude': 44.47,
              'longitude': -71.18,
              'admin1': 'New Hampshire',
              'country': 'United States',
            },
          ],
        },
      );
      final results = await client.searchLocations('Berlin');
      expect(results, hasLength(2));
      expect(results.first.displayLabel, 'Berlin, Berlin, Deutschland');
      expect(results.last.displayLabel, 'Berlin, New Hampshire, United States');
    });

    test('clearCache forces the next fetch to hit the network again', () async {
      adapter.when('GET', WeatherClient.forecastBaseUrl, statusCode: 200, body: _forecastBody());
      await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4);
      client.clearCache();
      await client.fetchCurrentWeather(latitude: 52.5, longitude: 13.4);
      expect(adapter.callCount, 2);
    });
  });
}
