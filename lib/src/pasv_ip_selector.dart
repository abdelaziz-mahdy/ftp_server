/// IP selection helper for the PASV/EPSV response advertised by
/// [FtpSession]. Split out of `ftp_session.dart` so it can be unit tested
/// without needing real sockets or a live `NetworkInterface.list()`.
///
/// This file lives under `lib/src/` because it is an implementation detail —
/// not part of the public API. Tests import it directly via
/// `package:ftp_server/src/pasv_ip_selector.dart`.
library;

/// A non-loopback, non-link-local IPv4 candidate discovered on a network
/// interface, tagged with the interface name it came from.
typedef PasvIpCandidate = ({String ip, String ifaceName});

/// Picks the local IPv4 address that should be advertised in a PASV/EPSV
/// response.
///
/// The selection rules mirror what mainstream FTP clients expect to see on
/// multi-interface hosts (notably Android phones, which simultaneously expose
/// `wlan0` → `192.168.x.x` and `rmnet*` → `10.x.x.x`):
///
///   1. [controlSocketAddress] — if it looks like a usable, routable address
///      (IPv4, not `0.0.0.0`, not loopback, not in the carrier-internal
///      `10.0.0.0/8` range). This is the most accurate source because it is
///      literally the address the client is already talking to.
///   2. An interface literally named `wlan0` (Android WiFi).
///   3. An interface literally named `en0` (iOS/macOS WiFi).
///   4. Any `192.168.*` candidate (home/office router).
///   5. Any `172.*` candidate (enterprise network).
///   6. Any `10.*` candidate (last resort — may be carrier-internal).
///   7. The first candidate in the list.
///   8. `"0.0.0.0"` if there is nothing else to return.
///
/// [controlSocketAddress] is expected to already be an IPv4 address string
/// (e.g. from `_controlSocket.address.address`) or `null` if the control
/// socket is not available / not IPv4.
///
/// [candidates] must already be filtered to non-loopback, non-link-local IPv4
/// addresses; this function does not re-filter them.
String selectPasvIp({
  required String? controlSocketAddress,
  required List<PasvIpCandidate> candidates,
}) {
  if (controlSocketAddress != null &&
      controlSocketAddress.isNotEmpty &&
      controlSocketAddress != '0.0.0.0' &&
      !controlSocketAddress.startsWith('127.') &&
      !controlSocketAddress.startsWith('10.')) {
    return controlSocketAddress;
  }

  if (candidates.isEmpty) return '0.0.0.0';

  return candidates.where((c) => c.ifaceName == 'wlan0').firstOrNull?.ip ??
      candidates.where((c) => c.ifaceName == 'en0').firstOrNull?.ip ??
      candidates.where((c) => c.ip.startsWith('192.168.')).firstOrNull?.ip ??
      candidates.where((c) => c.ip.startsWith('172.')).firstOrNull?.ip ??
      candidates.where((c) => c.ip.startsWith('10.')).firstOrNull?.ip ??
      candidates.first.ip;
}
