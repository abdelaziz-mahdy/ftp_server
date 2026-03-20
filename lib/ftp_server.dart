library;

import 'dart:io';
import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/tls_config.dart';
import 'logger_handler.dart';
import 'package:ftp_server/file_operations/file_operations.dart';

class FtpServer {
  ServerSocket? _server;
  SecureServerSocket? _secureServer;

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

  /// The security mode for this server (none, explicit, or implicit FTPS).
  final FtpSecurityMode securityMode;

  /// TLS configuration for FTPS modes.
  final TlsConfig? tlsConfig;

  /// Whether to require encrypted data connections (PROT P).
  /// Forced to true for implicit mode.
  final bool requireEncryptedData;

  /// The built SecurityContext, created from tlsConfig when securityMode != none.
  final SecurityContext? _securityContext;

  /// Active sessions. Sessions are automatically removed when they disconnect.
  final List<FtpSession> _sessionList = [];

  /// Get the list of current active sessions.
  List<FtpSession> get activeSessions => List.unmodifiable(_sessionList);

  /// Creates an FTP server with the provided configurations.
  ///
  /// The [port] is required to specify where the server will listen for connections.
  /// The [fileOperations] must be provided and handles all file/directory logic.
  /// The [serverType] determines the mode (read-only or read and write) of the server.
  /// Optional parameters include [username], [password], and [logFunction].
  /// For FTPS, provide [securityMode] and [tlsConfig].
  FtpServer(
    this.port, {
    this.username,
    this.password,
    required this.fileOperations,
    required this.serverType,
    this.securityMode = FtpSecurityMode.none,
    this.tlsConfig,
    bool requireEncryptedData = false,
    Function(String)? logFunction,
  })  : logger = LoggerHandler(logFunction),
        requireEncryptedData = securityMode == FtpSecurityMode.implicit
            ? true
            : requireEncryptedData,
        _securityContext = securityMode != FtpSecurityMode.none
            ? tlsConfig?.buildContext()
            : null {
    if (securityMode != FtpSecurityMode.none && tlsConfig == null) {
      throw ArgumentError(
        'tlsConfig is required when securityMode is not none',
      );
    }
    if (securityMode == FtpSecurityMode.none && tlsConfig != null) {
      logger.generalLog(
        'Warning: tlsConfig provided but securityMode is none; TLS config will be ignored',
      );
    }
  }

  FtpSession _createSession(Socket socket) {
    final bool implicitMode = securityMode == FtpSecurityMode.implicit;
    late FtpSession session;
    session = FtpSession(
      socket,
      username: username,
      password: password,
      fileOperations: fileOperations,
      serverType: serverType,
      logger: logger,
      securityContext: _securityContext,
      securityMode: securityMode,
      requireEncryptedData: requireEncryptedData,
      tlsActive: implicitMode,
      onDisconnect: () {
        _sessionList.remove(session);
      },
    );
    _sessionList.add(session);
    return session;
  }

  Future<void> start() async {
    if (securityMode == FtpSecurityMode.implicit) {
      _secureServer = await SecureServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        _securityContext!,
      );
      logger.generalLog('FTPS Server (implicit) is running on port $port');
      await for (var socket in _secureServer!) {
        logger.generalLog(
            'New client connected from ${socket.remoteAddress.address}:${socket.remotePort}');
        _createSession(socket);
      }
    } else {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      logger.generalLog('FTP Server is running on port $port');
      await for (var socket in _server!) {
        logger.generalLog(
            'New client connected from ${socket.remoteAddress.address}:${socket.remotePort}');
        _createSession(socket);
      }
    }
  }

  Future<void> startInBackground() async {
    if (securityMode == FtpSecurityMode.implicit) {
      _secureServer = await SecureServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        _securityContext!,
      );
      logger.generalLog('FTPS Server (implicit) is running on port $port');
      _secureServer!.listen((socket) {
        logger.generalLog(
            'New client connected from ${socket.remoteAddress.address}:${socket.remotePort}');
        _createSession(socket);
      });
    } else {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      logger.generalLog('FTP Server is running on port $port');
      _server!.listen((socket) {
        logger.generalLog(
            'New client connected from ${socket.remoteAddress.address}:${socket.remotePort}');
        _createSession(socket);
      });
    }
  }

  Future<void> stop() async {
    for (var session in List.of(_sessionList)) {
      session.closeConnection();
    }
    _sessionList.clear();
    await _server?.close();
    _server = null;
    await _secureServer?.close();
    _secureServer = null;
    logger.generalLog('FTP Server stopped');
  }
}
