import 'dart:async';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart' as plugin;
import 'package:logging/logging.dart';

class NetworkInfoService {
  static final _logger = Logger('NetworkInfoService');

  /// Fetches the IP address based on network connectivity changes
  static Future<String?> getDeviceIpAddress() async {
    final info = plugin.NetworkInfo();
    String? ipAddress;

    try {
      // Try to get the IP address from Wi-Fi
      ipAddress = await info.getWifiIP();
      if (ipAddress != null) {
        _logger.info('Wifi IP Address: $ipAddress');
        return ipAddress;
      }
    } catch (e) {
      _logger.warning('Failed to get wifi IP', e);
    }

    // Fallback to using dart:io to get IP from network interfaces
    try {
      final networkInterfaces = await NetworkInterface.list();
      final ipList = networkInterfaces
          .map((interface) => interface.addresses)
          .expand((ip) => ip)
          .where((ip) => ip.type == InternetAddressType.IPv4)
          .toList();

      // Filter IPs that start with '192'
      final wifiIp = ipList.firstWhere(
        (address) => address.address.startsWith('192'),
        orElse: () => ipList.first,
      );

      ipAddress = wifiIp.address;
      _logger.info('Fallback IP Address: $ipAddress');
    } catch (e, st) {
      _logger.severe('Failed to get IP address from network interfaces', e, st);
    }

    return ipAddress;
  }
}
