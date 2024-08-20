library ftp_server;

import 'dart:io';
import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'logger_handler.dart';
import 'file_operations/file_operations.dart';

class FtpServer {
  ServerSocket? _server;
  final int port;
  final String? username;
  final String? password;

  /// The file operations handler used by the FTP server to interact with the file system.
  ///
  /// This can be one of the following:
  ///
  /// - `PhysicalFileOperations`: For managing a single physical directory.
  ///   Example:
  ///   ```dart
  ///   fileOperations: PhysicalFileOperations('/home/user/ftp')
  ///   ```
  ///
  /// - `VirtualFileOperations`: For managing multiple directories as a single virtual root.
  ///   Example:
  ///   ```dart
  ///   fileOperations: VirtualFileOperations(['/home/user/ftp1', '/home/user/ftp2'])
  ///   ```
  final FileOperations fileOperations;
  final ServerType serverType;
  final LoggerHandler logger;

  /// Creates an FTP server with the provided configurations.
  FtpServer(
    this.port, {
    this.username,
    this.password,
    required this.fileOperations,
    required this.serverType,
    Function(String)? logFunction,
  }) : logger = LoggerHandler(logFunction);

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    logger.generalLog('FTP Server is running on port $port');
    await for (var client in _server!) {
      logger.generalLog(
          'New client connected from ${client.remoteAddress.address}:${client.remotePort}');
      FtpSession(
        client,
        username: username,
        password: password,
        fileOperations: fileOperations,
        serverType: serverType,
        logger: logger,
      );
    }
  }

  Future<void> startInBackground() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    logger.generalLog('FTP Server is running on port $port');
    _server!.listen((client) {
      logger.generalLog(
          'New client connected from ${client.remoteAddress.address}:${client.remotePort}');
      FtpSession(
        client,
        username: username,
        password: password,
        fileOperations: fileOperations,
        serverType: serverType,
        logger: logger,
      );
    });
  }

  Future<void> stop() async {
    await _server?.close();
    logger.generalLog('FTP Server stopped');
  }
}
