// lib/plain_socket_handler.dart
import 'dart:async';
import 'dart:io';
import 'socket_handler.dart';

class PlainSocketHandler implements SocketHandler {
  ServerSocket? _serverSocket;
  final StreamController<Socket> _controller = StreamController<Socket>();

  @override
  Future<void> bind(InternetAddress address, int port) async {
    _serverSocket = await ServerSocket.bind(address, port);
    _serverSocket!.listen((socket) {
      _controller.add(socket);
    });
  }

  @override
  Stream<Socket> get connections => _controller.stream;

  @override
  Future<Socket> accept() async {
    return await _serverSocket!.first;
  }

  @override
  void close() {
    _serverSocket?.close();
    _controller.close();
  }

  @override
  int? get port => _serverSocket?.port;
}
