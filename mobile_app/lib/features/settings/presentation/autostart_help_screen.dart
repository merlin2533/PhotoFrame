import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Pure informational screen listing OEM-specific autostart/battery
/// whitelisting steps (Xiaomi/MIUI, Huawei/EMUI, Samsung, OnePlus/OPPO/Vivo).
///
/// Deliberately does NOT try to deep-link into vendor-specific settings
/// pages programmatically (e.g. via package-specific Intents) - those paths
/// change across manufacturer skins/OS versions far too often to maintain
/// reliably, and a broken deep link is worse than a plain instruction. This
/// mirrors the same reasoning as `docs/DECISIONS.md` ADR-004 (Kiosk/Autostart
/// limits): be explicit about the OS/OEM boundary rather than papering over
/// it with fragile automation.
///
/// Reachable from Settings ("Autostart auf diesem Handy-Hersteller") and
/// also shown as an onboarding step (`onboarding_screen.dart`).
class AutostartHelpScreen extends StatelessWidget {
  const AutostartHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAutostartHelpTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.onboardingAutostartHintsIntro),
          const SizedBox(height: 16),
          _ManufacturerTile(
            icon: Icons.security_outlined,
            text: l10n.onboardingAutostartXiaomi,
          ),
          _ManufacturerTile(
            icon: Icons.shield_outlined,
            text: l10n.onboardingAutostartHuawei,
          ),
          _ManufacturerTile(
            icon: Icons.battery_std_outlined,
            text: l10n.onboardingAutostartSamsung,
          ),
          _ManufacturerTile(
            icon: Icons.phone_android_outlined,
            text: l10n.onboardingAutostartOnePlusOppoVivo,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.onboardingAutostartOutro,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _ManufacturerTile extends StatelessWidget {
  const _ManufacturerTile({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
