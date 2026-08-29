import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as socket_io;

/// A config-push notification as broadcast by the relay over the socket
/// (relay_server/src/routes/configPush.ts emits this to the target frame's
/// own `frame:<id>` room - not a pairing room - right after
/// `POST /config-push`). Carries only the push id + sender; the caller is
/// expected to fetch the full ciphertext via
/// `RelayApiClient.pendingConfigPushes()`.
class ConfigPushNotification {
  const ConfigPushNotification({required this.pushId, required this.senderFrameId});

  final String pushId;
  final String senderFrameId;
}

/// Connection lifecycle state exposed to the UI (e.g. a small status
/// indicator), independent of any particular pairing room.
enum RelaySocketState { disconnected, connecting, connected }

/// Thin wrapper around `socket_io_client` for the relay server's realtime
/// channel (relay_server/src/realtime/socket.ts).
///
/// Handshake auth is a device token (`auth: {token: <deviceToken>}`); the
/// server auto-joins the socket to `frame:<frameId>` on connect. Joining a
/// `pairing:<id>` room is an explicit opt-in via [joinPairing] because the
/// server re-validates membership at join time (a frame removed from a
/// pairing mid-connection must not keep listening in that room).
///
/// Honesty note on presence: the server does not currently broadcast any
/// "member online/offline" event - the only realtime event it emits is
/// `config_push`. Any "is this paired frame online" indicator in the UI is
/// therefore necessarily a heuristic (e.g. "we saw a socket event from
/// them recently" / "our own socket is connected") rather than a real
/// presence feed - see `pairing_screen.dart` for how that's surfaced
/// without overclaiming accuracy.
class RelaySocketClient {
  RelaySocketClient({required String baseUrl, required String deviceToken})
      : _baseUrl = baseUrl,
        _deviceToken = deviceToken;

  final String _baseUrl;
  final String _deviceToken;

  socket_io.Socket? _socket;

  final StreamController<RelaySocketState> _stateController =
      StreamController<RelaySocketState>.broadcast()..add(RelaySocketState.disconnected);
  final StreamController<ConfigPushNotification> _configPushController =
      StreamController<ConfigPushNotification>.broadcast();

  RelaySocketState _state = RelaySocketState.disconnected;

  Stream<RelaySocketState> get stateChanges => _stateController.stream;
  RelaySocketState get state => _state;

  /// Emits whenever the relay notifies this frame of a new pending
  /// config-push. Callers should treat this as a hint to re-fetch
  /// `/config-push/pending` (and run the config-push confirmation flow,
  /// including the TOFU fingerprint check) rather than trusting anything
  /// about the payload beyond `pushId`/`senderFrameId`.
  Stream<ConfigPushNotification> get configPushes => _configPushController.stream;

  void _setState(RelaySocketState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Opens the socket connection. Safe to call once; call [dispose] and
  /// construct a new client to reconnect with a different token.
  void connect() {
    if (_socket != null) return;

    _setState(RelaySocketState.connecting);

    final socket = socket_io.io(
      _baseUrl,
      socket_io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': _deviceToken})
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) => _setState(RelaySocketState.connected));
    socket.onDisconnect((_) => _setState(RelaySocketState.disconnected));
    socket.onConnectError((_) => _setState(RelaySocketState.disconnected));
    socket.onError((_) => _setState(RelaySocketState.disconnected));

    socket.on('config_push', (data) {
      if (data is Map) {
        final pushId = data['id'] as String?;
        final senderFrameId = data['senderFrameId'] as String?;
        if (pushId != null && senderFrameId != null) {
          _configPushController.add(ConfigPushNotification(pushId: pushId, senderFrameId: senderFrameId));
        }
      }
    });

    socket.connect();
  }

  /// Joins the `pairing:<pairingId>` room so this socket receives events
  /// scoped to that pairing (today: none beyond the frame-scoped
  /// `config_push`; kept for forward compatibility and because the server
  /// re-validates membership on join, which is itself a useful cheap
  /// "am I still a member" probe). Resolves to `true` on the server's ack.
  Future<bool> joinPairing(String pairingId) {
    final socket = _socket;
    if (socket == null) return Future.value(false);

    final completer = Completer<bool>();
    socket.emitWithAck('join_pairing', pairingId, ack: (dynamic response) {
      final ok = response is Map && response['ok'] == true;
      if (!completer.isCompleted) completer.complete(ok);
    });

    // socket_io_client's emitWithAck has no built-in timeout; guard against
    // a server that never acks (e.g. dropped connection mid-flight).
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    return completer.future;
  }

  void leavePairing(String pairingId) {
    _socket?.emit('leave_pairing', pairingId);
  }

  void disconnect() {
    _socket?.disconnect();
  }

  Future<void> dispose() async {
    _socket?.dispose();
    _socket = null;
    await _stateController.close();
    await _configPushController.close();
  }
}
