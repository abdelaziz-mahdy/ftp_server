// lib/socket_handler.dart
import 'dart:io';
import 'dart:async';

abstract class AbstractSocketHandler {
  Future<void> bind(InternetAddress address, int port);
  Stream<Socket> get connections;
  Future<Socket> accept();
  void close();
  int? get port;
}
