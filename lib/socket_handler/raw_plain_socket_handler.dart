import 'dart:async';
import 'dart:io';
import 'package:ftp_server/socket_wrapper/raw_socket_wrapper.dart';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';

import 'abstract_socket_handler.dart';

/// A socket handler using [RawServerSocket] for data channel connections.
///
/// Accepted connections are wrapped as [RawSocketWrapper], which can be
/// upgraded to [RawSecureSocketWrapper] for proper TLS shutdown control.
class RawPlainSocketHandler implements AbstractSocketHandler {
  RawServerSocket? _serverSocket;
  final StreamController<SocketWrapper> _controller =
      StreamController<SocketWrapper>();

  @override
  Future<void> bind(InternetAddress address, int port) async {
    _serverSocket = await RawServerSocket.bind(address, port);
    _serverSocket!.listen((rawSocket) {
      _controller.add(RawSocketWrapper(rawSocket));
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
