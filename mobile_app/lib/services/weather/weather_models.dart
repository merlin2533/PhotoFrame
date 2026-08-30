/// Simplified icon bucket that WMO weather codes are mapped into, so the
/// UI only ever has to switch on a handful of cases instead of ~30 raw
/// codes. See [weatherIconForWmoCode] for the mapping table.
enum WeatherIconKind {
  sunny,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  snow,
  thunderstorm,
  unknown,
}

/// Maps an Open-Meteo / WMO "weather code" (as returned by the
/// `current_weather.weathercode` field of https://api.open-meteo.com/v1/forecast)
/// to a simple [WeatherIconKind].
///
/// Table (per the WMO code standard Open-Meteo documents):
/// - 0                      -> sunny (clear sky)
/// - 1, 2                   -> partlyCloudy (mainly clear / partly cloudy)
/// - 3                      -> cloudy (overcast)
/// - 45, 48                 -> fog (incl. depositing rime fog)
/// - 51, 53, 55, 56, 57     -> drizzle (incl. freezing drizzle)
/// - 61, 63, 65, 66, 67     -> rain (incl. freezing rain)
/// - 80, 81, 82             -> rain (rain showers)
/// - 71, 73, 75, 77         -> snow (incl. snow grains)
/// - 85, 86                 -> snow (snow showers)
/// - 95, 96, 99             -> thunderstorm (incl. with hail)
/// - anything else          -> unknown
WeatherIconKind weatherIconForWmoCode(int code) {
  switch (code) {
    case 0:
      return WeatherIconKind.sunny;
    case 1:
    case 2:
      return WeatherIconKind.partlyCloudy;
    case 3:
      return WeatherIconKind.cloudy;
    case 45:
    case 48:
      return WeatherIconKind.fog;
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
      return WeatherIconKind.drizzle;
    case 61:
    case 63:
    case 65:
    case 66:
    case 67:
    case 80:
    case 81:
    case 82:
      return WeatherIconKind.rain;
    case 71:
    case 73:
    case 75:
    case 77:
    case 85:
    case 86:
      return WeatherIconKind.snow;
    case 95:
    case 96:
    case 99:
      return WeatherIconKind.thunderstorm;
    default:
      return WeatherIconKind.unknown;
  }
}

/// Current-conditions snapshot for one location, as parsed from Open-Meteo's
/// `current_weather` block.
class CurrentWeather {
  const CurrentWeather({
    required this.temperatureC,
    required this.weatherCode,
    required this.observedAt,
    required this.fetchedAt,
  });

  final double temperatureC;
  final int weatherCode;

  /// Timestamp the API reports the reading was taken (its local time at the
  /// queried coordinates).
  final DateTime observedAt;

  /// When this client fetched/cached the reading - used for cache expiry.
  final DateTime fetchedAt;

  WeatherIconKind get icon => weatherIconForWmoCode(weatherCode);

  /// Parses the `current_weather` object of an Open-Meteo forecast response,
  /// e.g. `{"temperature": 21.3, "weathercode": 3, "time": "2026-08-29T12:00"}`.
  factory CurrentWeather.fromCurrentWeatherJson(
    Map<String, dynamic> json, {
    required DateTime fetchedAt,
  }) {
    final timeRaw = json['time'] as String?;
    return CurrentWeather(
      temperatureC: (json['temperature'] as num).toDouble(),
      weatherCode: (json['weathercode'] as num).toInt(),
      observedAt: timeRaw != null
          ? (DateTime.tryParse(timeRaw) ?? fetchedAt)
          : fetchedAt,
      fetchedAt: fetchedAt,
    );
  }

  /// Parses a full forecast response `{"current_weather": {...}, ...}`.
  factory CurrentWeather.fromForecastResponseJson(
    Map<String, dynamic> json, {
    required DateTime fetchedAt,
  }) {
    final current = json['current_weather'] as Map<String, dynamic>?;
    if (current == null) {
      throw const FormatException('Open-Meteo response missing "current_weather"');
    }
    return CurrentWeather.fromCurrentWeatherJson(current, fetchedAt: fetchedAt);
  }
}

/// One candidate returned by the Open-Meteo Geocoding API
/// (https://geocoding-api.open-meteo.com/v1/search) for a city-name query.
class GeocodingResult {
  const GeocodingResult({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.admin1,
    this.country,
  });

  final String name;
  final double latitude;
  final double longitude;

  /// First-level administrative subdivision (state/region), if the API
  /// returned one - helps disambiguate same-named cities.
  final String? admin1;
  final String? country;

  /// Human-readable label to show in the picker list and persist as
  /// `AppSettings.weatherLocationLabel`, e.g. "Berlin, Deutschland" or
  /// "Springfield, Illinois, United States".
  String get displayLabel {
    final parts = [name, if (admin1 != null && admin1!.isNotEmpty) admin1, if (country != null && country!.isNotEmpty) country];
    return parts.join(', ');
  }

  factory GeocodingResult.fromJson(Map<String, dynamic> json) {
    return GeocodingResult(
      name: json['name'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      admin1: json['admin1'] as String?,
      country: json['country'] as String?,
    );
  }
}
