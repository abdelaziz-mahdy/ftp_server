// lib/socket_handler.dart
import 'dart:io';
import 'dart:async';

import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';

abstract class AbstractSocketHandler {
  Future<void> bind(InternetAddress address, int port);
  Stream<SocketWrapper> get connections;
  Future<SocketWrapper> accept();
  void close();
  int? get port;
}
