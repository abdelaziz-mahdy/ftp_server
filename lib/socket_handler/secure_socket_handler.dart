// lib/secure_socket_handler.dart
import 'dart:async';
import 'dart:io';
import 'socket_handler.dart';

class SecureSocketHandlerImpl implements SecureSocketHandler {
  @override
  SecurityContext securityContext;
  ServerSocket? _serverSocket;
  SecureServerSocket? _secureServerSocket;
  final StreamController<Socket> _controller = StreamController<Socket>();

  SecureSocketHandlerImpl(this.securityContext);

  @override
  Future<void> bind(InternetAddress address, int port) async {
    _serverSocket = await ServerSocket.bind(
      address,
      port,
    );

    _serverSocket!.listen((socket) async {
      // socket = await SecureSocket.secureServer(socket, securityContext);
      _controller.add(socket);
    });
  }

  @override
  Stream<Socket> get connections => _controller.stream;

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
  int? get port => _secureServerSocket?.port ?? _serverSocket?.port;
}
