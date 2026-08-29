import 'package:flutter/material.dart';

class AccessibilitySettingsScreen extends StatelessWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
