library;

import 'dart:io';
import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'logger_handler.dart';
import 'package:ftp_server/file_operations/file_operations.dart';

class FtpServer {
  ServerSocket? _server;

  /// The port on which the FTP server will listen for incoming connections.
  final int port;

  /// The username required for client authentication.
  ///
  /// This is optional and can be null if no authentication is required.
  final String? username;

  /// The password required for client authentication.
  ///
  /// This is optional and can be null if no authentication is required.
  final String? password;

  /// The server type defining the mode of the FTP server.
  ///
  /// - `ServerType.readOnly`: Only allows read operations (no write, delete, etc.).
  /// - `ServerType.readAndWrite`: Allows both read and write operations.
  final ServerType serverType;

  /// A logger handler used for logging various server events and commands.
  ///
  /// The `LoggerHandler` provides methods to log commands, responses, and general messages.
  final LoggerHandler logger;

  /// The file operations backend to use (VirtualFileOperations, PhysicalFileOperations, or custom).
  final FileOperations fileOperations;

  ///Create a List to collect new sessions.
  ///When you call _server?.stop() it should disconnect all active connections.
  final List<FtpSession> _sessionList = [];

  /// Get the list of current active sessions.
  List<FtpSession> get activeSessions => _sessionList;

  /// Creates an FTP server with the provided configurations.
  ///
  /// The [port] is required to specify where the server will listen for connections.
  /// The [fileOperations] must be provided and handles all file/directory logic.
  /// The [serverType] determines the mode (read-only or read and write) of the server.
  /// Optional parameters include [username], [password], and [logFunction].
  ///
  /// BREAKING CHANGE: `sharedDirectories` and `startingDirectory` are removed. All directory logic is now handled by the provided [fileOperations].
  FtpServer(this.port,
      {this.username,
      this.password,
      required this.fileOperations,
      required this.serverType,
      Function(String)? logFunction})
      : logger = LoggerHandler(logFunction);

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    logger.generalLog('FTP Server is running on port $port');
    await for (var socket in _server!) {
      logger.generalLog(
          'New client connected from ${socket.remoteAddress.address}:${socket.remotePort}');
      var session = FtpSession(
        socket,
        username: username,
        password: password,
        fileOperations: fileOperations,
        serverType: serverType,
        logger: logger,
      );
      //Fill sessionList with new sessions.
      _sessionList.add(session);
    }
  }

  Future<void> startInBackground() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    logger.generalLog('FTP Server is running on port $port');
    _server!.listen((socket) {
      logger.generalLog(
          'New client connected from ${socket.remoteAddress.address}:${socket.remotePort}');
      var session = FtpSession(
        socket,
        username: username,
        password: password,
        fileOperations: fileOperations,
        serverType: serverType,
        logger: logger,
      );
      //Fill sessionList with new sessions.
      _sessionList.add(session);
    });
  }

  Future<void> stop() async {
    //Disconnect all active sessions
    for (var session in _sessionList) {
      session.closeConnection();
    }
    _sessionList.clear();
    await _server?.close();
    _server = null;
    logger.generalLog('FTP Server stopped');
  }
}
