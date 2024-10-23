// lib/services/certificate_service.dart

import 'dart:async';
import 'dart:io';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';

class SecureSocketWrapper implements SocketWrapper {
  final SecureSocket _socket;

  SecureSocketWrapper(this._socket);

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

  /// Connects to the specified IP address and port using TLS.
  static Future<SecureSocketWrapper> connect(
    String ip,
    int port, {
    required SecurityContext securityContext,
  }) async {
    try {
      final socket = await SecureSocket.connect(
        ip,
        port,
        context: securityContext,
      );
      return SecureSocketWrapper(socket);
    } catch (e) {
      print('Error connecting (secure): $e'); // Or use your logger
      rethrow;
    }
  }

  @override
  void write(Object obj) => _socket.write(obj);
}
