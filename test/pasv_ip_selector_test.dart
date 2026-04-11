import 'package:ftp_server/src/pasv_ip_selector.dart';
import 'package:test/test.dart';

void main() {
  group('selectPasvIp', () {
    // ---- control socket fast-path ----

    test('control socket 192.168.* is returned directly', () {
      expect(
        selectPasvIp(
          controlSocketAddress: '192.168.1.10',
          candidates: [
            (ip: '10.85.1.1', ifaceName: 'rmnet0'),
          ],
        ),
        '192.168.1.10',
      );
    });

    test('control socket 172.16.* is returned directly', () {
      expect(
        selectPasvIp(
          controlSocketAddress: '172.16.5.3',
          candidates: [],
        ),
        '172.16.5.3',
      );
    });

    test('control socket 10.x falls through to interface scan', () {
      // Reproduces the Android bug: control socket sees the rmnet 10.x
      // address, but the real routable address is on wlan0.
      expect(
        selectPasvIp(
          controlSocketAddress: '10.85.1.1',
          candidates: [
            (ip: '192.168.1.10', ifaceName: 'wlan0'),
            (ip: '10.85.1.1', ifaceName: 'rmnet0'),
          ],
        ),
        '192.168.1.10',
      );
    });

    test('control socket 0.0.0.0 falls through to interface scan', () {
      expect(
        selectPasvIp(
          controlSocketAddress: '0.0.0.0',
          candidates: [(ip: '192.168.1.10', ifaceName: 'wlan0')],
        ),
        '192.168.1.10',
      );
    });

    test('control socket 127.* (loopback) falls through to interface scan', () {
      expect(
        selectPasvIp(
          controlSocketAddress: '127.0.0.1',
          candidates: [(ip: '192.168.1.10', ifaceName: 'eth0')],
        ),
        '192.168.1.10',
      );
    });

    test('null control socket falls through to interface scan', () {
      expect(
        selectPasvIp(
          controlSocketAddress: null,
          candidates: [(ip: '192.168.1.10', ifaceName: 'eth0')],
        ),
        '192.168.1.10',
      );
    });

    // ---- interface-name priority ----

    test('wlan0 wins over rmnet regardless of candidate order (Android)', () {
      expect(
        selectPasvIp(
          controlSocketAddress: null,
          candidates: [
            (ip: '10.85.1.1', ifaceName: 'rmnet0'),
            (ip: '192.168.1.10', ifaceName: 'wlan0'),
          ],
        ),
        '192.168.1.10',
      );
    });

    test('en0 wins when no wlan0 (iOS/macOS)', () {
      expect(
        selectPasvIp(
          controlSocketAddress: null,
          candidates: [
            (ip: '192.168.1.20', ifaceName: 'utun0'),
            (ip: '192.168.1.10', ifaceName: 'en0'),
          ],
        ),
        '192.168.1.10',
      );
    });

    test('wlan0 preferred over en0 when both are present', () {
      expect(
        selectPasvIp(
          controlSocketAddress: null,
          candidates: [
            (ip: '192.168.1.20', ifaceName: 'en0'),
            (ip: '192.168.1.10', ifaceName: 'wlan0'),
          ],
        ),
        '192.168.1.10',
      );
    });

    // ---- address-range priority ----

    test('192.168.* preferred over 172.* when no named WiFi interface', () {
      expect(
        selectPasvIp(
          controlSocketAddress: null,
          candidates: [
            (ip: '172.16.0.5', ifaceName: 'eth1'),
            (ip: '192.168.1.10', ifaceName: 'eth0'),
          ],
        ),
        '192.168.1.10',
      );
    });

    test('172.* preferred over 10.* when no 192.168.* or named WiFi', () {
      expect(
        selectPasvIp(
          controlSocketAddress: null,
          candidates: [
            (ip: '10.85.1.1', ifaceName: 'rmnet0'),
            (ip: '172.16.0.5', ifaceName: 'eth0'),
          ],
        ),
        '172.16.0.5',
      );
    });

    test('only 10.x available returns the 10.x (last-resort path)', () {
      expect(
        selectPasvIp(
          controlSocketAddress: null,
          candidates: [(ip: '10.85.1.1', ifaceName: 'rmnet0')],
        ),
        '10.85.1.1',
      );
    });

    // ---- fallbacks ----

    test('falls back to first candidate when nothing matches any rule', () {
      expect(
        selectPasvIp(
          controlSocketAddress: null,
          candidates: [
            (ip: '100.64.0.1', ifaceName: 'cgnat0'),
            (ip: '100.64.1.1', ifaceName: 'cgnat1'),
          ],
        ),
        '100.64.0.1',
      );
    });

    test('empty candidates with no control socket returns 0.0.0.0', () {
      expect(
        selectPasvIp(
          controlSocketAddress: null,
          candidates: [],
        ),
        '0.0.0.0',
      );
    });

    test('empty candidates with 10.x control socket returns 0.0.0.0', () {
      // The 10.x control socket is rejected, the candidate list is empty —
      // the function must not loop or throw, just return the sentinel.
      expect(
        selectPasvIp(
          controlSocketAddress: '10.85.1.1',
          candidates: [],
        ),
        '0.0.0.0',
      );
    });
  });
}
