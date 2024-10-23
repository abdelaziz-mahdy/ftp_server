// lib/plain_socket_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:ftp_server/socket_wrapper/plain_socket_wrapper.dart';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';

import 'abstract_socket_handler.dart';

class PlainSocketHandler implements AbstractSocketHandler {
  ServerSocket? _serverSocket;
  final StreamController<SocketWrapper> _controller =
      StreamController<SocketWrapper>();

  @override
  Future<void> bind(InternetAddress address, int port) async {
    _serverSocket = await ServerSocket.bind(address, port);
    _serverSocket!.listen((socket) {
      _controller.add(PlainSocketWrapper(socket));
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
    _serverSocket?.close();
    _controller.close();
  }

  @override
  int? get port => _serverSocket?.port;
}
