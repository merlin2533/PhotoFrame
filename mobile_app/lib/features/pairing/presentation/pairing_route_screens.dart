import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/config_push_apply.dart';
import '../state/pairing_providers.dart';
import 'config_push_confirmation_screen.dart';
import 'pairing_screen.dart';
import 'send_config_push_screen.dart';

/// Small `go_router`-facing shell around [PairingScreen] that resolves its
/// required [PairingRepository]/frame-id/pairing-id from the providers in
/// `pairing_providers.dart` instead of a caller having to thread them
/// through by hand.
///
/// Renders one of three states, in order:
///  1. No relay configured ([pairingRepositoryProvider] is `null`) -
///     [AppLocalizations.pairingNoRelayHint].
///  2. Relay configured but no pairing to show yet ([activePairingIdProvider]
///     or this device's own frame id is still `null`/unresolved) -
///     [AppLocalizations.pairingNoActivePairingHint]. An optional
///     `?pairingId=...` query parameter (persisted for next time) lets a
///     caller/deep-link set the active pairing explicitly - there is no
///     "list my pairings" UI yet (see `pairing_providers.dart` doc comment).
///  3. Otherwise, the real [PairingScreen].
class PairingRouteScreen extends ConsumerWidget {
  const PairingRouteScreen({super.key, this.queryPairingId});

  /// From the route's `?pairingId=...` query parameter, if present.
  final String? queryPairingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repository = ref.watch(pairingRepositoryProvider);
    if (repository == null) {
      return _Hint(title: l10n.settingsSharingTitle, message: l10n.pairingNoRelayHint);
    }

    final queryPairingId = this.queryPairingId;
    if (queryPairingId != null && queryPairingId.isNotEmpty) {
      unawaited(ref.read(relayTokenStorageProvider).saveActivePairingId(queryPairingId));
    }

    final storedPairingIdAsync = ref.watch(activePairingIdProvider);
    final localFrameIdAsync = ref.watch(localFrameIdProvider);

    final pairingId = queryPairingId ?? storedPairingIdAsync.valueOrNull;
    final localFrameId = localFrameIdAsync.valueOrNull;

    if (storedPairingIdAsync.isLoading || localFrameIdAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (pairingId == null || pairingId.isEmpty || localFrameId == null || localFrameId.isEmpty) {
      return _Hint(title: l10n.settingsSharingTitle, message: l10n.pairingNoActivePairingHint);
    }

    final fingerprintStore = ref.watch(keyFingerprintStoreProvider);
    final socketAsync = ref.watch(relaySocketClientProvider);

    return PairingScreen(
      pairingId: pairingId,
      localFrameId: localFrameId,
      repository: repository,
      fingerprintStore: fingerprintStore,
      socketClient: socketAsync.valueOrNull,
      onSendConfig: () => context.push('/settings/sharing/pairing/send?pairingId=$pairingId'),
    );
  }
}

/// Shell around [SendConfigPushScreen], resolving [PairingRepository] from
/// [pairingRepositoryProvider]. `pairingId` comes from the route's required
/// `?pairingId=...` query parameter (set by [PairingRouteScreen]'s "send
/// config" button) rather than [GoRouterState.extra] - a plain frame/pairing
/// id string encodes cleanly in a URL, unlike the [PendingConfigPush] object
/// used by [ConfigPushConfirmationRouteScreen] below.
class SendConfigPushRouteScreen extends ConsumerWidget {
  const SendConfigPushRouteScreen({super.key, required this.pairingId, this.initialTargetFrameId});

  final String pairingId;
  final String? initialTargetFrameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repository = ref.watch(pairingRepositoryProvider);
    if (repository == null) {
      return _Hint(title: l10n.settingsSharingTitle, message: l10n.pairingNoRelayHint);
    }
    return SendConfigPushScreen(
      pairingId: pairingId,
      repository: repository,
      initialTargetFrameId: initialTargetFrameId,
    );
  }
}

/// Shell around [ConfigPushConfirmationScreen]. [args] arrives via
/// [GoRouterState.extra] (see `pairing_providers.dart`'s
/// [ConfigPushConfirmationArgs] doc comment for why - a [PendingConfigPush]
/// carries a raw ciphertext blob with no clean URL encoding).
///
/// [ConfigPushConfirmationScreen.onAccept] is wired here to
/// [applyDecryptedConfigPush] - this is the one place in the routing layer
/// that turns "decryption succeeded" into "a new source is actually
/// registered".
class ConfigPushConfirmationRouteScreen extends ConsumerWidget {
  const ConfigPushConfirmationRouteScreen({super.key, required this.args});

  final ConfigPushConfirmationArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repository = ref.watch(pairingRepositoryProvider);
    if (repository == null) {
      return _Hint(title: l10n.settingsSharingTitle, message: l10n.pairingNoRelayHint);
    }

    return ConfigPushConfirmationScreen(
      push: args.push,
      senderLabel: args.senderLabel,
      repository: repository,
      onAccept: (plaintextJson) async {
        final result = await applyDecryptedConfigPush(
          plaintextJson,
          ref: ref,
          senderLabel: args.senderLabel,
        );
        if (!context.mounted) return;
        result.when(
          onOk: (_) => context.pop(),
          onErr: (failure) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure.message)),
          ),
        );
      },
      onReject: () => context.pop(),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message))),
    );
  }
}
