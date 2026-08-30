import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/weather/weather_models.dart';
import '../../../settings/state/settings_providers.dart';
import 'clock_overlay.dart';

IconData _iconFor(WeatherIconKind kind) {
  switch (kind) {
    case WeatherIconKind.sunny:
      return Icons.wb_sunny_rounded;
    case WeatherIconKind.partlyCloudy:
      return Icons.wb_cloudy_rounded;
    case WeatherIconKind.cloudy:
      return Icons.cloud_rounded;
    case WeatherIconKind.fog:
      return Icons.blur_on_rounded;
    case WeatherIconKind.drizzle:
      return Icons.grain_rounded;
    case WeatherIconKind.rain:
      return Icons.water_drop_rounded;
    case WeatherIconKind.snow:
      return Icons.ac_unit_rounded;
    case WeatherIconKind.thunderstorm:
      return Icons.bolt_rounded;
    case WeatherIconKind.unknown:
      return Icons.device_thermostat_rounded;
  }
}

/// Weather icon + temperature, no positioning/decoration - the raw content
/// reused both standalone (see [WeatherOverlay]) and combined with
/// [ClockText] into one info-bar pill in `slideshow_screen.dart`.
///
/// **Positioning decision** (documented here since it applies to both
/// [WeatherOverlay] and the combined-bar case in `slideshow_screen.dart`):
/// the weather reading is folded into the *same* bottom-left info bar as
/// the clock rather than given its own corner. Rationale:
/// - The screen only has two free corners for ambient overlays once
///   `SourceLabelOverlay` claims bottom-right per `docs/PLAN.md`; adding a
///   third independent pill (e.g. top-left) would clutter a device meant to
///   be looked at from across a room, and a temperature reading is
///   naturally companion information to a clock (this is also the
///   established pattern in comparable digital photo frames' clock/weather
///   widgets).
/// - Clock and weather are both small, glanceable, low-priority overlays;
///   grouping them lets a viewer take in "what time is it / what's it like
///   outside" in one glance instead of scanning two corners.
/// - When only one of the two is enabled, it still renders alone in the
///   bottom-left pill (see [ClockOverlay]/[WeatherOverlay]) - the combined
///   bar only forms when both are turned on, so enabling weather alone
///   doesn't force the clock on or move it.
///
/// Fetches lazily on mount and refreshes on [WeatherClient]'s own cache
/// cadence (default 45 min - see `weather_client.dart`) via a periodic
/// timer; the client's in-memory cache means re-mounting this widget (e.g.
/// after a settings change round-trip) does not trigger a redundant network
/// call within that window.
class WeatherOverlayContent extends ConsumerStatefulWidget {
  const WeatherOverlayContent({super.key});

  @override
  ConsumerState<WeatherOverlayContent> createState() => _WeatherOverlayContentState();
}

class _WeatherOverlayContentState extends ConsumerState<WeatherOverlayContent> {
  CurrentWeather? _weather;
  Object? _error;
  Timer? _refreshTimer;
  double? _lastLatitude;
  double? _lastLongitude;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) => _fetch());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    final lat = settings?.weatherLatitude;
    final lon = settings?.weatherLongitude;
    if (lat == null || lon == null) return;
    try {
      final weather = await ref.read(weatherClientProvider).fetchCurrentWeather(
            latitude: lat,
            longitude: lon,
          );
      if (mounted) setState(() => _weather = weather);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final lat = settings?.weatherLatitude;
    final lon = settings?.weatherLongitude;

    if (lat != _lastLatitude || lon != _lastLongitude) {
      _lastLatitude = lat;
      _lastLongitude = lon;
      if (lat != null && lon != null) {
        // Location changed (or became available) - kick off a fetch without
        // blocking build.
        scheduleMicrotask(_fetch);
      }
    }

    if (lat == null || lon == null) return const SizedBox.shrink();

    final weather = _weather;
    if (weather == null) {
      if (_error != null) {
        return const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 18);
      }
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_iconFor(weather.icon), color: Colors.white, size: 18),
        const SizedBox(width: 4),
        Text(
          '${weather.temperatureC.round()}°C',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Standalone weather pill, positioned bottom-left - used when weather is
/// enabled but the clock is not. See [WeatherOverlayContent]'s doc comment
/// for the positioning rationale and the combined-bar behaviour in
/// `slideshow_screen.dart`.
class WeatherOverlay extends StatelessWidget {
  const WeatherOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      left: 16,
      bottom: 16,
      child: InfoBarPill(child: WeatherOverlayContent()),
    );
  }
}
