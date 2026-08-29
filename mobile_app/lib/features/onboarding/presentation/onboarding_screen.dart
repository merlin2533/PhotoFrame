import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../settings/state/settings_providers.dart';

/// First-run setup wizard.
///
/// Explains what the app does, what "Dauer-Modus" (always-on display)
/// costs in terms of battery, and how to set the device up as a dedicated
/// photo frame (home-app/launcher + battery-optimization allowlist on
/// Android, "Guided Access" on iOS). Persisted via
/// `AppSettings.onboardingCompleted` so it only auto-shows once; reachable
/// again any time from Settings -> "Setup-Guide erneut anzeigen".
///
/// Design decision: rather than adding `android_intent_plus` (a native
/// platform-channel plugin) just to deep-link into the exact
/// "default apps -> home app" settings page, this screen uses the
/// `permission_handler` package (already a dependency) to open the app's
/// general settings page via `openAppSettings()`. That is not the precise
/// screen for choosing a home-app launcher, but it gets the user into
/// Android Settings in one tap without adding a new, less-maintained native
/// dependency for a single button; the accompanying text explains the exact
/// manual path ("Settings -> Apps -> Default apps -> Home app").
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const int _pageCount = 6;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish({required bool goToSources}) async {
    await ref.read(settingsProvider.notifier).markOnboardingCompleted();
    if (!mounted) return;
    if (goToSources) {
      context.go('/settings/sources/add');
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pageCount - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_page + 1) / _pageCount,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => _finish(goToSources: false),
                    child: const Text('Überspringen'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (p) => setState(() => _page = p),
                children: const [
                  _WelcomeStep(),
                  _AlwaysOnExplainerStep(),
                  _AndroidHomeAppStep(),
                  _AndroidBatteryOptimizationStep(),
                  _IosGuidedAccessStep(),
                  _AddSourceStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (_page > 0)
                    OutlinedButton(
                      onPressed: () => _goToPage(_page - 1),
                      child: const Text('Zurück'),
                    )
                  else
                    const SizedBox.shrink(),
                  const Spacer(),
                  FilledButton(
                    onPressed: isLast
                        ? () => _finish(goToSources: true)
                        : () => _goToPage(_page + 1),
                    child: Text(isLast ? 'Quelle hinzufügen' : 'Weiter'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
  });

  final IconData icon;
  final String title;
  final Widget body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          body,
          if (extra != null) ...[
            const SizedBox(height: 20),
            extra!,
          ],
        ],
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    return const _StepScaffold(
      icon: Icons.photo_library_outlined,
      title: 'Willkommen bei PhotoFrame',
      body: Text(
        'PhotoFrame verwandelt dieses Gerät in einen digitalen Fotorahmen: '
        'Es zeigt Bilder aus deinen Ordnern (z. B. Netzwerkfreigabe, '
        'Nextcloud oder lokaler Speicher) als Endlos-Diashow und kann Fotos '
        'mit anderen Frames teilen. Dieser kurze Guide richtet das Gerät in '
        'wenigen Schritten dafür ein.',
      ),
    );
  }
}

class _AlwaysOnExplainerStep extends StatelessWidget {
  const _AlwaysOnExplainerStep();

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      icon: Icons.brightness_high_outlined,
      title: 'Dauer-Modus: Bildschirm bleibt an',
      body: const Text(
        'Ein Fotorahmen soll dauerhaft leuchten - deshalb kann PhotoFrame '
        'verhindern, dass der Bildschirm ausgeht oder das Gerät sich sperrt. '
        'Das ist das Kernfeature dieser App, kostet aber spürbar Akku.',
      ),
      extra: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bolt, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Empfehlung: Dauer-Modus nur bei dauerhaft angeschlossenem '
                'Ladekabel verwenden (z. B. wandmontiert). Du kannst später '
                'in den Einstellungen zwischen "immer an", "nur während der '
                'Diashow" und einem Zeitplan (kombiniert mit dem Nachtmodus) '
                'wählen.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AndroidHomeAppStep extends StatelessWidget {
  const _AndroidHomeAppStep();

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid) {
      return const _StepScaffold(
        icon: Icons.android,
        title: 'Als Startbildschirm einrichten (Android)',
        body: Text(
          'Dieser Schritt betrifft nur Android-Geräte und wird auf diesem '
          'Gerät übersprungen.',
        ),
      );
    }
    return _StepScaffold(
      icon: Icons.android,
      title: 'Als Startbildschirm einrichten',
      body: const Text(
        'Damit PhotoFrame nach jedem Neustart automatisch erscheint, kannst '
        'du die App als Standard-Startbildschirm (Home-App/Launcher) '
        'festlegen: Android-Einstellungen -> Apps -> Standard-Apps -> '
        'Startbildschirm-App -> PhotoFrame auswählen.',
      ),
      extra: FilledButton.tonalIcon(
        onPressed: () => unawaited(ph.openAppSettings()),
        icon: const Icon(Icons.settings),
        label: const Text('Android-Einstellungen öffnen'),
      ),
    );
  }
}

class _AndroidBatteryOptimizationStep extends StatelessWidget {
  const _AndroidBatteryOptimizationStep();

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid) {
      return const _StepScaffold(
        icon: Icons.battery_charging_full_outlined,
        title: 'Von Akku-Optimierung ausnehmen (Android)',
        body: Text(
          'Dieser Schritt betrifft nur Android-Geräte und wird auf diesem '
          'Gerät übersprungen.',
        ),
      );
    }
    return _StepScaffold(
      icon: Icons.battery_charging_full_outlined,
      title: 'Von Akku-Optimierung ausnehmen',
      body: const Text(
        'Android beendet App-Aktivität im Hintergrund gerne, um Akku zu '
        'sparen - das kann die Diashow ausbremsen oder Bilder verzögert '
        'aktualisieren. Nimm PhotoFrame in den Einstellungen unter '
        '"Akku -> Nicht optimieren"/"Akkuoptimierung ignorieren" aus der '
        'Optimierung aus, damit sie dauerhaft zuverlässig läuft.',
      ),
      extra: FilledButton.tonalIcon(
        onPressed: () => unawaited(ph.openAppSettings()),
        icon: const Icon(Icons.settings),
        label: const Text('App-Einstellungen öffnen'),
      ),
    );
  }
}

class _IosGuidedAccessStep extends StatelessWidget {
  const _IosGuidedAccessStep();

  @override
  Widget build(BuildContext context) {
    return const _StepScaffold(
      icon: Icons.lock_clock_outlined,
      title: 'iOS: Geführter Zugriff',
      body: Text(
        'iOS erlaubt Apps grundsätzlich keinen Autostart und keinen echten '
        'Kiosk-Modus. Der ehrliche, zuverlässige Weg auf iPhone/iPad ist der '
        'systemeigene "Geführte Zugriff" (Einstellungen -> Bedienungshilfen '
        '-> Geführter Zugriff aktivieren, danach dreimal die Seitentaste '
        'drücken, während PhotoFrame geöffnet ist). Das muss nach jedem '
        'Neustart des Geräts manuell erneut gestartet werden - das ist eine '
        'Plattformgrenze, keine Einschränkung dieser App.',
      ),
    );
  }
}

class _AddSourceStep extends StatelessWidget {
  const _AddSourceStep();

  @override
  Widget build(BuildContext context) {
    return const _StepScaffold(
      icon: Icons.add_photo_alternate_outlined,
      title: 'Quelle hinzufügen',
      body: Text(
        'Fast geschafft! Füge jetzt eine Bildquelle hinzu (z. B. einen '
        'lokalen Ordner, eine Netzwerkfreigabe oder Nextcloud), damit die '
        'Diashow starten kann. Du kannst das auch später jederzeit über '
        'Einstellungen -> Quellen erledigen.',
      ),
    );
  }
}

bool get _isAndroid {
  try {
    return Platform.isAndroid;
  } catch (_) {
    // Platform is unavailable on web/some test hosts.
    return false;
  }
}
