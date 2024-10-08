// lib/socket_handler.dart
import 'dart:io';
import 'dart:async';

abstract class SocketHandler {
  Future<void> bind(InternetAddress address, int port);
  Stream<Socket> get connections;
  Future<Socket> accept();
  void close();
  int? get port;
}

abstract class SecureSocketHandler extends SocketHandler {
  SecurityContext securityContext;
  SecureSocketHandler(this.securityContext);
}
