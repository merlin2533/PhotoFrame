import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/relay/relay_socket_client.dart';
import '../domain/key_fingerprint.dart';
import '../domain/pairing_models.dart';
import '../domain/pairing_repository.dart';

/// Overview of one [Pairing]: member list (with a best-effort online
/// indicator and TOFU status), invite/leave/delete actions, and - for the
/// local frame's owner - the ability to remove another member.
class PairingScreen extends StatefulWidget {
  const PairingScreen({
    super.key,
    required this.pairingId,
    required this.localFrameId,
    required this.repository,
    required this.fingerprintStore,
    this.socketClient,
    this.onInvite,
    this.onSendConfig,
  });

  final String pairingId;
  final String localFrameId;
  final PairingRepository repository;
  final KeyFingerprintStore fingerprintStore;

  /// Optional: when provided, its connection state and `config_push`
  /// events are used for the best-effort presence indicator described in
  /// the class doc comment on [_PresenceHeuristic].
  final RelaySocketClient? socketClient;

  final VoidCallback? onInvite;

  /// Navigates to `send_config_push_screen.dart` (see
  /// `pairing_providers.dart`/`app_router.dart` for the route that wires
  /// this up with a live [PairingRepository]). `null` hides the button(s) -
  /// used by tests that construct this screen without a router in scope.
  ///
  /// Called with a specific member's `frameId` from the per-member "send
  /// config to this device" action (pre-fills the target so the payload -
  /// SMB host/user/password in cleartext once decrypted - can't be
  /// misdirected to the wrong pairing member by a typo in a free-text
  /// field, found in review), or with `null` from the general FAB when the
  /// user wants to type/paste a target frame id themselves.
  final void Function(String? targetFrameId)? onSendConfig;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

/// Best-effort "is this frame online" indicator.
///
/// Honesty note: relay_server/src/realtime/socket.ts does not broadcast
/// any member online/offline/presence event - the only realtime event is
/// `config_push`. So this can only ever be a heuristic:
///  - the LOCAL frame is "online" iff our own socket is connected.
///  - any OTHER member is "recently active" if we saw a `config_push`
///    naming them as sender within the last [_recentWindow] - otherwise
///    its status is shown as "unknown", never as a false "offline".
class _PresenceHeuristic {
  static const Duration recentWindow = Duration(minutes: 2);

  final Map<String, DateTime> _lastSeen = {};

  void markSeen(String frameId) => _lastSeen[frameId] = DateTime.now();

  bool isRecentlyActive(String frameId) {
    final seen = _lastSeen[frameId];
    if (seen == null) return false;
    return DateTime.now().difference(seen) < recentWindow;
  }
}

enum _MemberStatus { onlineLocal, recentlyActive, unknown }

class _PairingScreenState extends State<PairingScreen> {
  final _presence = _PresenceHeuristic();
  StreamSubscription<ConfigPushNotification>? _pushSub;
  StreamSubscription<RelaySocketState>? _stateSub;

  Pairing? _pairing;
  RelaySocketState _socketState = RelaySocketState.disconnected;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _pushSub = widget.socketClient?.configPushes.listen((event) {
      _presence.markSeen(event.senderFrameId);
      if (mounted) setState(() {});
    });
    _stateSub = widget.socketClient?.stateChanges.listen((state) {
      if (mounted) setState(() => _socketState = state);
    });
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.repository.getPairing(widget.pairingId);
    if (!mounted) return;
    result.when(
      onOk: (pairing) => setState(() => _pairing = pairing),
      onErr: (failure) => setState(() => _error = failure.message),
    );
    setState(() => _loading = false);
  }

  _MemberStatus _statusFor(PairingMember member) {
    if (member.frameId == widget.localFrameId) {
      return _socketState == RelaySocketState.connected ? _MemberStatus.onlineLocal : _MemberStatus.unknown;
    }
    return _presence.isRecentlyActive(member.frameId) ? _MemberStatus.recentlyActive : _MemberStatus.unknown;
  }

  Color _statusColor(_MemberStatus status) {
    switch (status) {
      case _MemberStatus.onlineLocal:
      case _MemberStatus.recentlyActive:
        return Colors.green;
      case _MemberStatus.unknown:
        return Colors.grey;
    }
  }

  Future<FingerprintTrust?> _peekTrust(PairingMember member) async {
    if (member.keyFingerprint == null) return null;
    final trusted = await widget.fingerprintStore.trustedFingerprintFor(member.frameId);
    if (trusted == null) return null; // never displayed before - not a mismatch, just unestablished.
    return trusted == member.keyFingerprint ? FingerprintTrust.match : FingerprintTrust.mismatch;
  }

  Future<void> _removeMember(PairingMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerät entfernen'),
        content: Text('Soll "${member.frameId}" wirklich aus dieser Gruppe entfernt werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entfernen')),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await widget.repository.removeMember(widget.pairingId, member.frameId);
    if (!mounted) return;
    result.when(
      onOk: (_) => _load(),
      onErr: (failure) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    final isOwner = pairing?.isOwnedBy(widget.localFrameId) ?? false;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(pairing?.name ?? 'Pairing'),
        actions: [
          IconButton(icon: const Icon(Icons.person_add), onPressed: widget.onInvite, tooltip: 'Gerät einladen'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: widget.onSendConfig == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => widget.onSendConfig!(null),
              icon: const Icon(Icons.send_outlined),
              label: Text(l10n.pairingSendConfigButton),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  children: [
                    for (final member in pairing!.members)
                      FutureBuilder<FingerprintTrust?>(
                        future: _peekTrust(member),
                        builder: (context, snapshot) {
                          final trust = snapshot.data;
                          final status = _statusFor(member);
                          return ListTile(
                            leading: Icon(Icons.circle, size: 12, color: _statusColor(status)),
                            title: Text(member.frameId == widget.localFrameId
                                ? '${member.frameId} (dieses Gerät)'
                                : member.frameId),
                            subtitle: Text(
                              '${member.isOwner ? "Besitzer" : "Mitglied"}'
                              '${trust == FingerprintTrust.mismatch ? " · Sicherheitsschlüssel geändert!" : ""}',
                              style: trust == FingerprintTrust.mismatch
                                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                                  : null,
                            ),
                            trailing: member.frameId == widget.localFrameId
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.onSendConfig != null)
                                        IconButton(
                                          icon: const Icon(Icons.send_outlined),
                                          tooltip: l10n.pairingSendConfigButton,
                                          onPressed: () => widget.onSendConfig!(member.frameId),
                                        ),
                                      if (isOwner)
                                        IconButton(
                                          icon: const Icon(Icons.person_remove),
                                          onPressed: () => _removeMember(member),
                                        ),
                                    ],
                                  ),
                          );
                        },
                      ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Diese Gruppe verlassen'),
                      onTap: () async {
                        final result = await widget.repository.leave(widget.pairingId);
                        if (context.mounted) {
                          result.when(
                            onOk: (_) => Navigator.of(context).maybePop(),
                            onErr: (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message))),
                          );
                        }
                      },
                    ),
                    if (isOwner)
                      ListTile(
                        leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                        title: const Text('Gruppe löschen'),
                        onTap: () async {
                          final result = await widget.repository.deletePairing(widget.pairingId);
                          if (context.mounted) {
                            result.when(
                              onOk: (_) => Navigator.of(context).maybePop(),
                              onErr: (f) =>
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message))),
                            );
                          }
                        },
                      ),
                  ],
                ),
    );
  }
}
