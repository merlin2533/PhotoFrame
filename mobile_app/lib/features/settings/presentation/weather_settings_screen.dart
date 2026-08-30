import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../services/weather/weather_models.dart';
import '../state/settings_providers.dart';

/// Weather-overlay settings: on/off toggle, current configured location, a
/// manual city-search picker (the default/primary path - see class doc
/// below), and an opt-in "aktuellen Standort verwenden" convenience button.
///
/// **Manual entry is the default and primary path, by design**: this is a
/// kiosk-style device typically left plugged in and never touched again, so
/// there is no ongoing need for live GPS and no reason to request a
/// permission most users would find surprising for a "digital photo frame"
/// app. Real geolocation (via `geolocator`) is offered purely as a
/// convenience for the initial setup and always requires an explicit tap +
/// OS permission grant - it is never used implicitly or in the background.
class WeatherSettingsScreen extends ConsumerStatefulWidget {
  const WeatherSettingsScreen({super.key});

  @override
  ConsumerState<WeatherSettingsScreen> createState() => _WeatherSettingsScreenState();
}

class _WeatherSettingsScreenState extends ConsumerState<WeatherSettingsScreen> {
  final _searchController = TextEditingController();
  List<GeocodingResult> _results = const [];
  bool _searching = false;
  bool _locating = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await ref.read(weatherClientProvider).searchLocations(query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Suche fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectLocation(GeocodingResult result) async {
    await ref.read(settingsProvider.notifier).updateSettings(
          (s) => s.copyWith(
            weatherLatitude: result.latitude,
            weatherLongitude: result.longitude,
            weatherLocationLabel: result.displayLabel,
          ),
        );
    if (mounted) {
      setState(() {
        _results = const [];
        _searchController.clear();
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _error =
            'Standortzugriff verweigert. Bitte manuell eine Stadt eingeben oder die Berechtigung in den System-Einstellungen erteilen.');
        return;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _error = 'Standortdienste sind auf diesem Gerät deaktiviert.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      await ref.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(
              weatherLatitude: position.latitude,
              weatherLongitude: position.longitude,
              weatherLocationLabel: 'Aktueller Standort',
            ),
          );
    } catch (e) {
      if (mounted) setState(() => _error = 'Standort konnte nicht ermittelt werden: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Wetter')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wetter-Overlay anzeigen'),
              subtitle: const Text('Temperatur + Wettersymbol in der Diashow'),
              value: settings.weatherEnabled,
              onChanged: (v) => notifier.updateSettings((s) => s.copyWith(weatherEnabled: v)),
            ),
            const Divider(height: 32),
            Text('Ort', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(settings.weatherLocationLabel ?? 'Kein Ort ausgewählt'),
                subtitle: settings.weatherLatitude != null && settings.weatherLongitude != null
                    ? Text(
                        '${settings.weatherLatitude!.toStringAsFixed(2)}, '
                        '${settings.weatherLongitude!.toStringAsFixed(2)}',
                      )
                    : const Text('Stadt suchen oder aktuellen Standort verwenden'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Stadt suchen',
                hintText: 'z. B. Berlin',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onSubmitted: _search,
            ),
            if (_results.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Column(
                  children: _results
                      .map(
                        (r) => ListTile(
                          title: Text(r.displayLabel),
                          onTap: () => _selectLocation(r),
                        ),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _locating ? null : _useCurrentLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: const Text('Aktuellen Standort verwenden'),
            ),
            const SizedBox(height: 4),
            const Text(
              'Optional - erfordert eine Berechtigung. Manuelle Ortseingabe '
              'oben ist der Standardweg und benötigt keinen Standortzugriff.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
