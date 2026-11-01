import 'dart:io';

/// Self-signed certificates are common on a home server, so an invalid
/// certificate is only tolerated for hosts in the local network (localhost,
/// `.local`/`.lan` names, private IPv4 ranges). The API key is never sent to
/// a public host with an invalid certificate.
bool isPrivateHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.lan')) {
    return true;
  }
  final ip = InternetAddress.tryParse(h);
  if (ip == null) return false;
  if (ip.isLoopback || ip.isLinkLocal) return true;
  if (ip.type == InternetAddressType.IPv4) {
    final b = ip.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }
  // IPv6 unique local addresses (fc00::/7).
  return ip.rawAddress[0] & 0xfe == 0xfc;
}
