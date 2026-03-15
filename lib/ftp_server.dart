library;

import 'dart:io';
import 'dart:async';

import 'package:ftp_server/certificate_service.dart';
import 'package:ftp_server/socket_handler/plain_socket_handler.dart';
import 'package:ftp_server/socket_handler/secure_socket_handler.dart';
import 'package:ftp_server/socket_handler/abstract_socket_handler.dart';

import 'ftp_session.dart';
import 'server_type.dart';
import 'logger_handler.dart';
import 'package:ftp_server/file_operations/file_operations.dart';

class FtpServer {
  late AbstractSocketHandler _socketHandler;

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

  /// Create a List to collect new sessions.
  /// When you call _server?.stop() it should disconnect all active connections.
  final List<FtpSession> _sessionList = [];

  /// Get the list of current active sessions.
  List<FtpSession> get activeSessions => _sessionList;

  /// Whether the server will only accept secure connections using TLS (implicit FTPS).
  ///
  /// If `true`, the server will only accept connections that are secured using TLS.
  /// If `false`, the server will accept normal FTP connections and can optionally be
  /// upgraded to TLS using the command `AUTH TLS` if [secureConnectionAllowed] is `true`.
  final bool enforceSecureConnections;

  /// Whether the server will accept secure data connections using TLS.
  ///
  /// If `true`, the server will only accept data connections that are secured using TLS.
  /// If `false`, the server will accept normal FTP data connections.
  /// Note: clients can override this per-session via the PROT command after AUTH TLS.
  final bool secureDataConnection;

  /// Whether the server will be able to upgrade to TLS using the `AUTH TLS` command (explicit FTPS).
  final bool secureConnectionAllowed;

  /// The security context for the server.
  /// A [securityContext] can be provided or it will be created automatically.
  SecurityContext? securityContext;

  /// Creates an FTP server with the provided configurations.
  ///
  /// The [port] is required to specify where the server will listen for connections.
  /// The [fileOperations] must be provided and handles all file/directory logic.
  /// The [serverType] determines the mode (read-only or read and write) of the server.
  /// Optional parameters include [username], [password], and [logFunction].
  FtpServer(
    this.port, {
    this.username,
    this.password,
    required this.fileOperations,
    required this.serverType,
    Function(String)? logFunction,
    this.enforceSecureConnections = false,
    this.secureDataConnection = false,
    this.secureConnectionAllowed = false,
    this.securityContext,
  }) : logger = LoggerHandler(logFunction) {
    // Generate a security context if TLS is needed and none was provided
    if (enforceSecureConnections || secureConnectionAllowed) {
      securityContext ??=
          CertificateService.generateSecurityContext().createSecurityContext();
    }

    if (enforceSecureConnections) {
      _socketHandler = SecureSocketHandler(securityContext!);
    } else {
      _socketHandler = PlainSocketHandler();
    }
  }

  Future<void> _startServer() async {
    await _socketHandler.bind(InternetAddress.anyIPv4, port);
  }

  Future<void> start() async {
    await _startServer();
    logger.generalLog('FTP Server is running on port $port');

    await for (var client in _socketHandler.connections) {
      logger.generalLog(
          'New client connected from ${client.remoteAddress.address}:${client.remotePort}');
      var session = FtpSession(
        client,
        username: username,
        password: password,
        fileOperations: fileOperations,
        serverType: serverType,
        logger: logger,
        secure: enforceSecureConnections,
        secureDataConnection: secureDataConnection,
        secureConnectionAllowed: secureConnectionAllowed,
        securityContext: securityContext,
      );
      _sessionList.add(session);
    }
  }

  Future<void> startInBackground() async {
    await _startServer();
    logger.generalLog('FTP Server is running on port $port');

    _socketHandler.connections.listen((client) {
      logger.generalLog(
          'New client connected from ${client.remoteAddress.address}:${client.remotePort}');
      var session = FtpSession(
        client,
        username: username,
        password: password,
        fileOperations: fileOperations,
        serverType: serverType,
        logger: logger,
        secure: enforceSecureConnections,
        secureDataConnection: secureDataConnection,
        secureConnectionAllowed: secureConnectionAllowed,
        securityContext: securityContext,
      );
      _sessionList.add(session);
    });
  }

  Future<void> stop() async {
    for (var session in _sessionList) {
      session.closeConnection();
    }
    _sessionList.clear();
    _socketHandler.close();
    logger.generalLog('FTP Server stopped');
  }
}
