// lib/secure_socket_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:ftp_server/socket_handler/abstract_secure_socket_handler.dart';
import 'package:ftp_server/socket_wrapper/secure_socket_wrapper.dart';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';

class SecureSocketHandler implements AbstractSecureSocketHandler {
  @override
  SecurityContext securityContext;
  SecureServerSocket? _secureServerSocket;

  final StreamController<SocketWrapper> _controller =
      StreamController<SocketWrapper>();

  SecureSocketHandler(this.securityContext);

  @override
  Future<void> bind(InternetAddress address, int port) async {
    _secureServerSocket = await SecureServerSocket.bind(
      address,
      port,
      securityContext,
    );

    _secureServerSocket!.listen((socket) async {
      // socket = await SecureSocket.secureServer(socket, securityContext);
      _controller.add(SecureSocketWrapper(socket));
    });
  }

  @override
  Stream<SocketWrapper> get connections => _controller.stream;

  @override
  Future<SocketWrapper> accept() async {
    return await connections.first;
  }

  @override
  void close() {
    _secureServerSocket?.close();
    _controller.close();
  }

  @override
  int? get port => _secureServerSocket?.port;
}
