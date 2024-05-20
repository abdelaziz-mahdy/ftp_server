library ftp_server;

import 'dart:io';
import 'package:ftp_server/file_operations/in_memory_file_operations.dart';
import 'package:ftp_server/server_type.dart';

import 'command_handler/ftp_command_handler.dart';
import 'file_system/in_memory_file_system.dart';
import 'session/concrete_ftp_session.dart';
import 'session/context/session_context.dart';

import 'file_operations/concrete_file_operations.dart';

class FtpServer {
  ServerSocket? _server;
  final int port;
  final String? username;
  final String? password;
  final List<String> allowedDirectories;
  final String startingDirectory;
  final ServerType serverType;

  FtpServer(
    this.port, {
    this.username,
    this.password,
    required this.allowedDirectories,
    required this.startingDirectory,
    required this.serverType,
  });

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    print('FTP Server is running on port $port');
    var rootDirectory = InMemoryFtpDirectory('/');

    await for (var client in _server!) {
      print(
          'New client connected from ${client.remoteAddress.address}:${client.remotePort}');
      ConcreteFtpSession(
        SessionContext(
          controlSocket: client,
          currentDirectory: startingDirectory,
          allowedDirectories: allowedDirectories,
          serverType: serverType,
          startingDirectory: startingDirectory,
          username: username,
          password: password,
        ),
        commandHandler: ConcreteFTPCommandHandler(client),
        fileOperations: ConcreteFileOperations(),
        // memory one can be used too
        //fileOperations: InMemoryFileOperations(rootDirectory),
      );
    }
  }

  Future<void> stop() async {
    await _server?.close();
    print('FTP Server stopped');
  }
}
