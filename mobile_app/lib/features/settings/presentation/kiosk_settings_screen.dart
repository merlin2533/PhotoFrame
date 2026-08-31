import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../slideshow/state/slideshow_providers.dart';
import '../state/settings_providers.dart';

/// Settings page for the Android kiosk/autostart toggle (see
/// docs/DECISIONS.md ADR-004): lets the user opt into registering the app
/// as selectable as the device's Home app (see AndroidManifest.xml) and
/// activating screen pinning while the slideshow runs (see
/// `slideshow_screen.dart`/`KioskModeController`).
///
/// Deliberately honest about what this toggle can and cannot do - see
/// [_KioskExplanation] below - since neither step can be forced
/// programmatically:
///  - The "use as Home app" system dialog still requires the user's own
///    confirmation the next time they press Home.
///  - Unprivileged screen pinning (no Device Owner/MDM rights) can still
///    show a small "unpin"/"exit" affordance at the top of the screen -
///    that is platform behaviour this app cannot suppress.
class KioskSettingsScreen extends ConsumerWidget {
  const KioskSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final kioskController = ref.read(kioskModeControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.kioskScreenTitle)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.commonError(e.toString()))),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.kioskIntro),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.kioskToggleTitle),
              subtitle: Text(l10n.kioskToggleSubtitle),
              value: settings.kioskModeEnabled,
              onChanged: (value) {
                notifier.updateSettings((s) => s.copyWith(kioskModeEnabled: value));
                // Found on a real device: turning this off only updated the
                // persisted setting - screen pinning (if currently active)
                // stayed in effect until the slideshow screen happened to be
                // rebuilt/disposed, with no way for the user to tell whether
                // turning the switch off actually did anything. Stop
                // pinning immediately instead; starting it here too (rather
                // than only from slideshow_screen.dart on next entry) is
                // harmless and keeps both directions instant.
                if (value) {
                  unawaited(kioskController.start());
                } else {
                  unawaited(kioskController.stop());
                }
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => unawaited(kioskController.stop()),
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(l10n.kioskExitNowButton),
            ),
            const Divider(height: 32),
            _KioskExplanation(icon: Icons.home_outlined, text: l10n.kioskHomeAppNote),
            const SizedBox(height: 12),
            _KioskExplanation(icon: Icons.push_pin_outlined, text: l10n.kioskPinningNote),
            const SizedBox(height: 12),
            _KioskExplanation(icon: Icons.android_outlined, text: l10n.kioskAndroidOnlyNote),
          ],
        ),
      ),
    );
  }
}

class _KioskExplanation extends StatelessWidget {
  const _KioskExplanation({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ],
    );
  }
}
