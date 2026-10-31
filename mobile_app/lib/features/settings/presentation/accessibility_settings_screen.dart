import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_settings.dart';
import '../state/settings_providers.dart';

class AccessibilitySettingsScreen extends ConsumerWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final notifier = ref.read(settingsProvider.notifier);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      appBar: AppBar(title: const Text('Barrierefreiheit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'PhotoFrame respektiert die System-Einstellung "Bewegung '
            'reduzieren": ist sie aktiv, werden Ken-Burns-Effekt und '
            'Bild-Übergänge automatisch abgeschaltet, unabhängig von den '
            'Diashow-Einstellungen. Das verhindert vestibuläre Beschwerden '
            'bei Nutzer:innen, die dafür empfindlich sind.',
          ),
          const SizedBox(height: 16),
          Text('Textgröße: ${(settings.textScale * 100).round()} %',
              style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: settings.textScale,
            min: 1.0,
            max: 1.6,
            divisions: 6,
            label: '${(settings.textScale * 100).round()} %',
            onChanged: (v) =>
                notifier.updateSettings((s) => s.copyWith(textScale: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hoher Kontrast'),
            subtitle: const Text('Stärkere Farben für Text und Anzeigen'),
            value: settings.highContrast,
            onChanged: (v) =>
                notifier.updateSettings((s) => s.copyWith(highContrast: v)),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                reduceMotion ? Icons.check_circle : Icons.info_outline,
                color: reduceMotion ? Colors.green : null,
              ),
              title: const Text('Bewegung reduzieren (System-Einstellung)'),
              subtitle: Text(
                reduceMotion
                    ? 'Aktiv - Ken-Burns/Übergänge sind derzeit deaktiviert'
                    : 'Nicht aktiv - Einstellung befindet sich im Betriebssystem',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
