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
  /// This method wraps the plain socket in a `SecureSocket`, allowing
  /// secure communication using the provided `SecurityContext`.
  ///
  /// Returns a [SecureSocketWrapper] on success, or throws an error on failure.
  Future<SecureSocketWrapper> upgradeToSecure({
    required SecurityContext securityContext,
  }) async {
    try {
      return SecureSocketWrapper(
        await SecureSocket.secureServer(
          _socket,
          securityContext,
        ),
      );
    } catch (e) {
      print("Upgrade failed: $e");
      rethrow;
    }
  }

  /// Connects to the specified IP address and port using plain socket connection.
  ///
  /// Returns a [PlainSocketWrapper] on successful connection.
  /// Throws an error if the connection fails.
  static Future<PlainSocketWrapper> connect(
    String ip,
    int port,
  ) async {
    try {
      final socket = await Socket.connect(ip, port);
      return PlainSocketWrapper(socket);
    } catch (e) {
      print('Error connecting: $e');
      rethrow;
    }
  }

  @override
  void write(Object obj) => _socket.write(obj);

  @override
  int get port => _socket.port;

  @override
  int get remotePort => _socket.remotePort;

  @override
  InternetAddress get address => _socket.address;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
}
