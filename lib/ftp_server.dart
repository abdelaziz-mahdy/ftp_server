library ftp_server;

import 'dart:io';
import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'logger_handler.dart';

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

  /// A list of directories that the FTP server will expose to clients.
  ///
  /// These directories are accessible by clients connected to the FTP server.
  /// The list must not be empty, otherwise an [ArgumentError] will be thrown.
  final List<String> sharedDirectories;

  /// The starting directory for the FTP session.
  ///
  /// This is optional and specifies the initial directory for the FTP session. It must be
  /// within the [sharedDirectories]. If null, the session starts in the first directory of
  /// [sharedDirectories].
  final String? startingDirectory;

  /// Creates an FTP server with the provided configurations.
  ///
  /// The [port] is required to specify where the server will listen for connections.
  /// The [sharedDirectories] specifies which directories are accessible through the FTP server and must be provided.
  /// The [serverType] determines the mode (read-only or read and write) of the server.
  /// Optional parameters include [username] and [password] for authentication and a [logFunction] for custom logging.
  FtpServer(this.port,
      {this.username,
      this.password,
      required this.sharedDirectories,
      required this.serverType,
      Function(String)? logFunction,
      this.startingDirectory})
      : logger = LoggerHandler(logFunction) {
    if (sharedDirectories.isEmpty) {
      throw ArgumentError("Shared directories cannot be empty");
    }
  }

  ///Create a List to collect new sessions.
  ///When you call _server?.stop() it should disconnect all active connections.
  List<FtpSession> sessionList = [];

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    logger.generalLog('FTP Server is running on port $port');
    await for (var socket in _server!) {
      logger.generalLog(
          'New socket connected from ${socket.remoteAddress.address}:${socket.remotePort}');
      var session = FtpSession(
        socket,
        username: username,
        password: password,
        sharedDirectories: sharedDirectories,
        serverType: serverType,
        startingDirectory: startingDirectory,
        logger: logger,
      );
      //Fill sessionList with new sessions.
      sessionList.add(session);
    }
  }

  Future<void> startInBackground() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    logger.generalLog('FTP Server is running on port $port');
    _server!.listen((client) {
      logger.generalLog(
          'New client connected from ${client.remoteAddress.address}:${client.remotePort}');
      var session = FtpSession(
        socket,
        username: username,
        password: password,
        sharedDirectories: sharedDirectories,
        serverType: serverType,
        startingDirectory: startingDirectory,
        logger: logger,
      );
      //Fill sessionList with new sessions.
      sessionList.add(session);
    });
  }

  Future<void> stop() async {
    //Disconnect all active sessions
    for (var session in sessionList) {
      session.closeConnection();
    }
    await _server?.close();
    _server = null;
    logger.generalLog('FTP Server stopped');
  }
}
