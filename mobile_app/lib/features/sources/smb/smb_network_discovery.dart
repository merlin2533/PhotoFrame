import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

/// One SMB/NetBIOS host discovered on the local network, offered to the user
/// as a pick instead of typing an IP by hand.
class DiscoveredSmbHost {
  const DiscoveredSmbHost({
    required this.host,
    required this.address,
    this.port,
    this.viaMdns = true,
  });

  /// Hostname (mDNS service target or NetBIOS name), without trailing dot.
  final String host;

  /// Resolved IP address.
  final InternetAddress address;

  /// SMB port, when advertised (mDNS SRV record). `null` for NetBIOS-only
  /// results, where the standard port 445 should be assumed by the caller.
  final int? port;

  /// Whether this host was found via mDNS (`true`) or the NetBIOS fallback
  /// (`false`).
  final bool viaMdns;

  @override
  String toString() =>
      'DiscoveredSmbHost(host: $host, address: ${address.address}, port: $port, viaMdns: $viaMdns)';
}

/// Best-effort discovery of SMB hosts on the local network, so
/// `smb_config_form.dart` can offer a "search network" button instead of
/// requiring a manually typed host/IP (see docs/PLAN.md "SMB-Netzwerk-
/// Discovery"). Purely a convenience: manual entry must always remain
/// available, since multicast is frequently blocked on guest/isolated Wi-Fi
/// networks and this whole feature can legitimately find nothing.
class SmbNetworkDiscovery {
  SmbNetworkDiscovery({MDnsClient? mdnsClient})
      : _mdnsClient = mdnsClient ?? MDnsClient();

  final MDnsClient _mdnsClient;

  static const String _smbServiceType = '_smb._tcp.local';

  /// Searches for SMB hosts advertising `_smb._tcp.local` via mDNS/Bonjour
  /// (common on modern NAS devices and Avahi-enabled Samba setups). Returns
  /// whatever was found within [timeout]; an empty list is a normal, expected
  /// outcome (no such host, or multicast blocked on this network) - not an
  /// error.
  Future<List<DiscoveredSmbHost>> discoverViaMdns({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final results = <DiscoveredSmbHost>[];
    try {
      await _mdnsClient.start();
      await for (final ptr in _mdnsClient
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_smbServiceType),
          )
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        await for (final srv in _mdnsClient
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )
            .timeout(timeout, onTimeout: (sink) => sink.close())) {
          await for (final ip in _mdnsClient
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              )
              .timeout(timeout, onTimeout: (sink) => sink.close())) {
            results.add(
              DiscoveredSmbHost(
                host: srv.target,
                address: ip.address,
                port: srv.port,
              ),
            );
          }
        }
      }
    } catch (_) {
      // Discovery is best-effort: swallow and just return whatever was
      // found so far (possibly nothing) rather than surfacing a scary error
      // for what is a pure UX convenience.
    } finally {
      _mdnsClient.stop();
    }
    return results;
  }

  /// NetBIOS name resolution fallback for older Windows-style shares that
  /// don't advertise themselves via mDNS/Bonjour at all.
  ///
  /// UNVERIFIED - based on the classic NetBIOS Name Service (NBNS, RFC 1002)
  /// wire format, not tested against a real Windows/Samba host in this
  /// environment (no network hardware available here - see docs/PLAN.md M1
  /// SMB spike). NBNS is a legacy broadcast-based protocol (UDP/137); many
  /// modern routers/APs with client isolation or IGMP snooping quirks will
  /// simply drop these broadcasts, in which case this returns an empty list
  /// exactly like "nothing found" - manual IP entry remains the safety net.
  Future<List<DiscoveredSmbHost>> discoverViaNetbios({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final found = <DiscoveredSmbHost>[];
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // NBNS "Node Status Request" broadcast to the standard NetBIOS name
      // service port. Encodes a wildcard name query per RFC 1002 ยง4.2.
      final packet = _buildNbnsNodeStatusQuery();
      socket.send(packet, InternetAddress('255.255.255.255'), 137);

      final completer = Completer<void>();
      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        final name = _parseNbnsNodeStatusResponse(datagram.data);
        if (name != null) {
          found.add(
            DiscoveredSmbHost(
              host: name,
              address: datagram.address,
              viaMdns: false,
            ),
          );
        }
      });

      await Future.any([
        completer.future,
        Future<void>.delayed(timeout),
      ]);
      await sub.cancel();
    } catch (_) {
      // Best-effort, see doc comment above.
    } finally {
      socket?.close();
    }
    return found;
  }

  /// Runs both discovery mechanisms and merges results (mDNS first, since it
  /// is the verified/actively-maintained path; NetBIOS results are appended
  /// as a fallback for hosts mDNS didn't find).
  Future<List<DiscoveredSmbHost>> discoverAll() async {
    final mdnsResults = await discoverViaMdns();
    final netbiosResults = await discoverViaNetbios();
    final seenAddresses = mdnsResults.map((h) => h.address.address).toSet();
    return [
      ...mdnsResults,
      ...netbiosResults.where((h) => !seenAddresses.contains(h.address.address)),
    ];
  }

  List<int> _buildNbnsNodeStatusQuery() {
    // Minimal RFC 1002 NBNS header + wildcard "*" encoded name question for
    // a Node Status ("NBSTAT") request. Transaction id is fixed since we
    // don't correlate responses to a specific request here.
    final bytes = <int>[
      0x13, 0x37, // Transaction ID
      0x00, 0x00, // Flags: standard query
      0x00, 0x01, // Questions: 1
      0x00, 0x00, // Answer RRs
      0x00, 0x00, // Authority RRs
      0x00, 0x00, // Additional RRs
    ];
    // Encoded NetBIOS wildcard name "*" padded to 16 bytes, first-level
    // encoded per RFC 1001 into 32 half-octets (A-P alphabet).
    const rawName = '*               '; // 16 chars: '*' + 15 spaces
    bytes.add(32); // length of encoded name that follows
    for (final codeUnit in rawName.codeUnits) {
      final hi = (codeUnit >> 4) & 0xF;
      final lo = codeUnit & 0xF;
      bytes.add(0x41 + hi);
      bytes.add(0x41 + lo);
    }
    bytes.add(0x00); // name terminator
    bytes.addAll([0x00, 0x21]); // QTYPE = NBSTAT (0x0021)
    bytes.addAll([0x00, 0x01]); // QCLASS = IN
    return bytes;
  }

  String? _parseNbnsNodeStatusResponse(List<int> data) {
    // A full NBSTAT response parse is out of scope for this best-effort
    // fallback; we only try to recover the first 15-byte NetBIOS name from
    // the answer resource record, which is "good enough" to offer the user
    // a host label. Any parsing failure is treated as "no usable name".
    try {
      if (data.length < 57) return null;
      // Name entry count is a single byte located after the fixed NBSTAT
      // RR header (header(12) + name(34) + type/class/ttl/rdlength(10) = 56).
      final nameCount = data[56];
      if (nameCount == 0) return null;
      final nameBytes = data.sublist(57, 57 + 15);
      final name = String.fromCharCodes(nameBytes).trim();
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _mdnsClient.stop();
  }
}
