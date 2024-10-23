// lib/services/certificate_service.dart

import 'dart:async';
import 'dart:io';
import 'package:ftp_server/socket_wrapper/secure_socket_wrapper.dart';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';

class PlainSocketWrapper implements SocketWrapper {
  final Socket _socket;

  PlainSocketWrapper(this._socket);

  @override
  Future<void> close() => _socket.close();

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  Future<void> flush() => _socket.flush();

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _socket.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  void destroy() => _socket.destroy();

  /// Upgrades the plain socket to a secure socket (TLS).
  ///
  /// Returns a [Future] that completes with a [SecureSocketWrapper] if the upgrade is successful,
  /// or throws an exception if it fails.
  Future<SecureSocketWrapper> upgradeToSecure({
    required SecurityContext securityContext,
  }) async {
    try {
      return SecureSocketWrapper(await SecureSocket.secureServer(
        _socket,
        securityContext,
        // onBadCertificate: (X509Certificate cert) => true, // Handle certificate validation if needed
      ));
    } catch (e) {
      // Handle upgrade errors (e.g., certificate issues, network problems)
      print("Upgrade failed: $e"); // Or use your logger
      rethrow; // Re-throw the exception to be handled by the caller
    }
  }

  /// Connects to the specified IP address and port.
  static Future<PlainSocketWrapper> connect(
    String ip,
    int port,
  ) async {
    try {
      final socket = await Socket.connect(ip, port);
      return PlainSocketWrapper(socket);
    } catch (e) {
      print('Error connecting: $e'); // Or use your logger
      rethrow;
    }
  }

  @override
  void write(Object obj) => _socket.write(obj);
}
