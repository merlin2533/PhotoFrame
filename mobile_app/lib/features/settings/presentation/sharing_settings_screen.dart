import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../state/settings_providers.dart';

/// Relay-server URL configuration only. The actual pairing/QR-code flow
/// (`pairing_screen.dart`, `pairing_qr_display_screen.dart`, ...) is being
/// built by a parallel agent per `docs/PLAN.md` -> `features/pairing/`; this
/// screen intentionally stops at "here's the URL field and a placeholder
/// button into that flow" so the two pieces of work don't collide.
class SharingSettingsScreen extends ConsumerStatefulWidget {
  const SharingSettingsScreen({super.key});

  @override
  ConsumerState<SharingSettingsScreen> createState() =>
      _SharingSettingsScreenState();
}

class _SharingSettingsScreenState extends ConsumerState<SharingSettingsScreen> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).valueOrNull;
    _urlController = TextEditingController(text: settings?.relayServerUrl ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Sharing/Relay')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Trage die Basis-URL deines selbst gehosteten Relay-Servers '
              'ein, um Frames zu koppeln und Bilder zu teilen (HTTPS wird '
              'empfohlen; eine unverschlüsselte LAN-Adresse ist als Opt-out '
              'möglich).',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Relay-Server-URL',
                hintText: 'https://mein-relay.example.com',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => notifier.updateSettings(
                (s) => v.trim().isEmpty
                    ? s.copyWith(clearRelayServerUrl: true)
                    : s.copyWith(relayServerUrl: v.trim()),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => notifier.updateSettings(
                (s) => _urlController.text.trim().isEmpty
                    ? s.copyWith(clearRelayServerUrl: true)
                    : s.copyWith(relayServerUrl: _urlController.text.trim()),
              ),
              child: const Text('Speichern'),
            ),
            const Divider(height: 32),
            Builder(builder: (context) {
              final l10n = AppLocalizations.of(context);
              final hasRelayUrl = settings.relayServerUrl != null && settings.relayServerUrl!.isNotEmpty;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.qr_code_2_outlined),
                title: const Text('Pairing / Gerät koppeln'),
                subtitle: Text(hasRelayUrl ? '' : l10n.pairingNoRelayHint),
                enabled: hasRelayUrl,
                trailing: const Icon(Icons.chevron_right),
                onTap: hasRelayUrl ? () => context.push('/settings/sharing/pairing') : null,
              );
            }),
          ],
        ),
      ),
    );
  }
}
