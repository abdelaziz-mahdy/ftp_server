library ftp_server;

import 'dart:io';
import 'package:ftp_server/ftp_session.dart';
import 'ftp_session.dart';

class FtpServer {
  ServerSocket? _server;
  final int port;
  final String? username;
  final String? password;
  final List<String> allowedDirectories;
  final String startingDirectory;

  FtpServer(this.port, {this.username, this.password, required this.allowedDirectories, required this.startingDirectory});

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    print('FTP Server is running on port $port');
    await for (var client in _server!) {
      print('New client connected from ${client.remoteAddress.address}:${client.remotePort}');
      FtpSession(
        client,
        username: username,
        password: password,
        allowedDirectories: allowedDirectories,
        startingDirectory: startingDirectory,
      );
    }
  }

  Future<void> stop() async {
    await _server?.close();
    print('FTP Server stopped');
  }
}
