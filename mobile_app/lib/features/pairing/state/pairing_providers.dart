import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/relay/relay_api_client.dart';
import '../../../services/relay/relay_socket_client.dart';
import '../../../services/relay/relay_token_storage.dart';
import '../../settings/state/settings_providers.dart';
import '../data/relay_pairing_repository.dart';
import '../domain/key_fingerprint.dart';
import '../domain/pairing_models.dart';
import '../domain/pairing_repository.dart';

/// Single, app-lifetime [RelayTokenStorage] instance backing every relay
/// provider below - mirrors the "one shared instance via Riverpod" pattern
/// already used for [FrameKeypairStore]-adjacent services elsewhere in this
/// feature.
final Provider<RelayTokenStorage> relayTokenStorageProvider =
    Provider<RelayTokenStorage>((ref) => RelayTokenStorage());

final Provider<KeyFingerprintStore> keyFingerprintStoreProvider =
    Provider<KeyFingerprintStore>((ref) => KeyFingerprintStore());

/// Builds a [RelayApiClient] from the persisted [AppSettings.relayServerUrl].
///
/// Returns `null` - deliberately, rather than throwing - whenever no relay
/// URL is configured yet, so callers (`sharing_settings_screen.dart`,
/// `pairing_providers.dart`'s own [pairingRepositoryProvider]) can render a
/// clear "set up a relay server first" hint instead of the app crashing on
/// an unconfigured feature.
final Provider<RelayApiClient?> relayApiClientProvider = Provider<RelayApiClient?>((ref) {
  final relayServerUrl = ref.watch(settingsProvider.select((s) => s.valueOrNull?.relayServerUrl));
  if (relayServerUrl == null || relayServerUrl.isEmpty) return null;
  final tokenStorage = ref.watch(relayTokenStorageProvider);
  return RelayApiClient(baseUrl: relayServerUrl, tokenStorage: tokenStorage);
});

/// Builds (and connects) a [RelaySocketClient] for the realtime `config_push`
/// channel, from [relayApiClientProvider]'s origin plus this device's stored
/// device token.
///
/// A [FutureProvider] rather than a plain [Provider] because reading the
/// device token from secure storage is inherently async; resolves to `null`
/// - never throws - whenever there is no relay configured yet
/// ([relayApiClientProvider] is `null`) or this device hasn't registered a
/// frame yet (no device token), both of which callers must treat the same
/// way as "nothing to connect to right now".
final FutureProvider<RelaySocketClient?> relaySocketClientProvider =
    FutureProvider<RelaySocketClient?>((ref) async {
  final api = ref.watch(relayApiClientProvider);
  if (api == null) return null;

  final tokenStorage = ref.watch(relayTokenStorageProvider);
  final deviceToken = await tokenStorage.deviceToken;
  if (deviceToken == null) return null;

  final client = RelaySocketClient(baseUrl: api.socketOrigin, deviceToken: deviceToken);
  client.connect();
  ref.onDispose(() {
    unawaited(client.dispose());
  });
  return client;
});

/// Builds a [PairingRepository] on top of [relayApiClientProvider] and
/// [keyFingerprintStoreProvider]. `null` under the same "no relay configured
/// yet" condition as [relayApiClientProvider] - callers must show a
/// "Relay-Server einrichten" hint rather than assume a non-null repository.
final Provider<PairingRepository?> pairingRepositoryProvider = Provider<PairingRepository?>((ref) {
  final api = ref.watch(relayApiClientProvider);
  if (api == null) return null;
  final fingerprintStore = ref.watch(keyFingerprintStoreProvider);
  return RelayPairingRepository(apiClient: api, fingerprintStore: fingerprintStore);
});

/// The pairing id this device most recently opened `PairingScreen` for,
/// remembered across app restarts (see [RelayTokenStorage.activePairingId]
/// doc comment for why this "last active pairing" memory - rather than a
/// real "list my pairings" server endpoint - is this iteration's deliberate
/// scope boundary).
final FutureProvider<String?> activePairingIdProvider = FutureProvider<String?>((ref) async {
  final tokenStorage = ref.watch(relayTokenStorageProvider);
  return tokenStorage.activePairingId;
});

/// This device's own relay frame id, once registered
/// (`relay_server_setup_screen.dart`). `null` before that has happened.
final FutureProvider<String?> localFrameIdProvider = FutureProvider<String?>((ref) async {
  final tokenStorage = ref.watch(relayTokenStorageProvider);
  return tokenStorage.frameId;
});

/// Arguments passed via [GoRouterState.extra] to the
/// `config-push-confirm` route, since a [PendingConfigPush] (its raw
/// ciphertext especially) has no clean, size-bounded URL encoding - see
/// `app_router.dart` for the route definition and the project-wide note on
/// introducing `extra` there.
class ConfigPushConfirmationArgs {
  const ConfigPushConfirmationArgs({required this.push, required this.senderLabel});

  final PendingConfigPush push;
  final String senderLabel;
}

/// Wraps the app (installed via `MaterialApp.router`'s `builder`) to
/// globally subscribe to [relaySocketClientProvider]'s `configPushes` stream
/// and navigate to the config-push confirmation route whenever one arrives -
/// this is what makes an incoming push actionable without the user having to
/// already be on `PairingScreen` when it lands.
///
/// KNOWN LIMITATION (see task handoff notes): the realtime `config_push`
/// event only carries `pushId`/`senderFrameId`, not which [Pairing] it
/// belongs to (relay_server/src/realtime/socket.ts emits to a per-frame
/// room, not a per-pairing one). Resolving the full [PendingConfigPush] via
/// [PairingRepository.pendingConfigPushes] needs a `pairingId` - this widget
/// uses [activePairingIdProvider] (the last pairing the user opened
/// `PairingScreen` for) as a best-effort stand-in. If that is `null`, or
/// refers to a pairing the sender isn't actually a member of, the
/// notification is silently dropped rather than guessing - the push stays
/// pending server-side and is picked up correctly the next time the user
/// opens `PairingScreen` for the right pairing (which re-fetches
/// `pendingConfigPushes` itself). This could not be exercised end-to-end in
/// this environment (no second physical device/relay deployment available).
class ConfigPushListener extends ConsumerStatefulWidget {
  const ConfigPushListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ConfigPushListener> createState() => _ConfigPushListenerState();
}

class _ConfigPushListenerState extends ConsumerState<ConfigPushListener> {
  StreamSubscription<ConfigPushNotification>? _subscription;
  RelaySocketClient? _attachedClient;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RelaySocketClient?>>(relaySocketClientProvider, (previous, next) {
      final client = next.valueOrNull;
      if (identical(client, _attachedClient)) return;
      _subscription?.cancel();
      _attachedClient = client;
      _subscription = client?.configPushes.listen(_handleNotification);
    });
    return widget.child;
  }

  Future<void> _handleNotification(ConfigPushNotification event) async {
    final repository = ref.read(pairingRepositoryProvider);
    final pairingId = await ref.read(activePairingIdProvider.future);
    final localFrameId = await ref.read(localFrameIdProvider.future);
    if (repository == null || pairingId == null || localFrameId == null) return;

    final result = await repository.pendingConfigPushes(
      pairingId: pairingId,
      localFrameId: localFrameId,
    );
    final pushes = result.valueOrNull;
    if (pushes == null) return;

    PendingConfigPush? match;
    for (final push in pushes) {
      if (push.id == event.pushId) {
        match = push;
        break;
      }
    }
    if (match == null) return;

    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null || !navigatorContext.mounted) return;

    // Deliberately no display name lookup beyond the raw frame id - the
    // relay currently exposes no human-friendly device name for members
    // (see `PairingMember`), only `frameId` itself.
    unawaited(GoRouter.of(navigatorContext).push(
      '/settings/sharing/pairing/confirm-push',
      extra: ConfigPushConfirmationArgs(push: match, senderLabel: event.senderFrameId),
    ));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Root [Navigator] key for the app's [GoRouter] (see `app_router.dart`),
/// shared here so [ConfigPushListener] - which lives above the router, in
/// `MaterialApp.router`'s `builder` - can resolve a [BuildContext] to call
/// `GoRouter.of(context).push(...)` from outside the routed widget tree,
/// where no local [BuildContext] is otherwise available.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
