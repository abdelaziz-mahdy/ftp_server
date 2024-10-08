// lib/secure_socket_handler.dart
import 'dart:async';
import 'dart:io';
import 'socket_handler.dart';

class SecureSocketHandlerImpl implements SecureSocketHandler {
  @override
  SecurityContext securityContext;
  SecureServerSocket? _secureServerSocket;
  final StreamController<SecureSocket> _controller =
      StreamController<SecureSocket>();

  SecureSocketHandlerImpl(this.securityContext);

  @override
  Future<void> bind(InternetAddress address, int port) async {
    _secureServerSocket = await SecureServerSocket.bind(
      address,
      port,
      securityContext,
    );
    _secureServerSocket!.listen((socket) {
      _controller.add(socket);
    });
  }

  @override
  Stream<SecureSocket> get connections => _controller.stream;

  @override
  Future<SecureSocket> accept() async {
    return await _secureServerSocket!.first;
  }

  @override
  void close() {
    _secureServerSocket?.close();
    _controller.close();
  }

  @override
  int? get port => _secureServerSocket?.port;
}
