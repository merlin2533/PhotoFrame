/// Seam for ambient light readings (lux) from a device light sensor.
///
/// No platform implementation exists yet: the app has no light-sensor plugin
/// in `pubspec.yaml`. A real implementation (e.g. wrapping the `light`
/// package) must be added by someone who can run `flutter pub get` and test
/// on a device. Until then the default [NoopAmbientLightSource] is used.
abstract class AmbientLightSource {
  /// Ambient light readings in lux. May never emit (see the no-op default).
  Stream<double> get lux;
}

/// Default source for platforms without a light sensor. Never emits a value,
/// so ambient dimming falls back to its time window alone.
class NoopAmbientLightSource implements AmbientLightSource {
  const NoopAmbientLightSource();

  @override
  Stream<double> get lux => const Stream<double>.empty();
}
