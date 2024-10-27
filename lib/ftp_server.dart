// lib/ftp_server.dart
library ftp_server;

import 'dart:io';
import 'dart:async';

import 'package:ftp_server/certificate_service.dart';
import 'package:ftp_server/socket_handler/plain_socket_handler.dart';
import 'package:ftp_server/socket_handler/secure_socket_handler.dart';
import 'package:ftp_server/socket_handler/abstract_socket_handler.dart';

import 'ftp_session.dart';
import 'server_type.dart';
import 'logger_handler.dart';

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

  /// Whether the server will only accept secure connections using TLS or not.
  ///
  /// If `true`, the server will only accept connections that are secured using TLS.
  /// If `false`, the server will accept normal FTP connections and can optionally be upgraded to TLS using the command `AUTH TLS` if [secureConnectionAllowed] is `true`.
  ///
  /// Even if this is set to `false`, the server will still accept TLS upgrades, but it will not be the default.
  /// If a client wants to upgrade to TLS, it can still send the `AUTH TLS` command.
  ///
  /// A [securityContext] can be provided or it will be created automatically.
  final bool enforceSecureConnections;

  /// Whether the server will only accept secure connections using TLS or not in data connections.
  ///
  /// If `true`, the server will only accept connections that are secured using TLS.
  /// If `false`, the server will accept normal FTP data connections.
  final bool secureDataConnection;

  /// Whether the server will be able to upgrade to TLS using the `AUTH TLS` command.
  final bool secureConnectionAllowed;

  /// the security context for the server
  /// a [securityContext] can be provided or it will be created automatically
  SecurityContext? securityContext;

  /// Creates an FTP server with the provided configurations.
  ///
  /// The [port] is required to specify where the server will listen for connections.
  /// The [sharedDirectories] specifies which directories are accessible through the FTP server and must be provided.
  /// The [serverType] determines the mode (read-only or read and write) of the server.
  /// Optional parameters include [username] and [password] for authentication and a [logFunction] for custom logging.
  FtpServer(
    this.port, {
    this.username,
    this.password,
    required this.sharedDirectories,
    required this.serverType,
    Function(String)? logFunction,
    this.startingDirectory,
    this.enforceSecureConnections = false,
    this.secureDataConnection = false,
    this.secureConnectionAllowed = false,
    this.securityContext,
  }) : logger = LoggerHandler(logFunction) {
    if (sharedDirectories.isEmpty) {
      throw ArgumentError("Shared directories cannot be empty");
    }

    // Initialize the appropriate SocketHandler based on the 'secure' flag
    // if (secure) {
    //   securityContext ??= SecurityContext.defaultContext;
    //   if (securityContext == null) {
    //     throw ArgumentError(
    //         "SecurityContext must be provided for secure connections");
    //   }
    //   _socketHandler = SecureSocketHandlerImpl(securityContext!);
    // } else {
    // if (secure) {
    //   // securityContext ??= SecurityContext.defaultContext;

    //   securityContext ??=
    //       CertificateService.generateSecurityContext().createSecurityContext();
    //   _socketHandler = SecureSocketHandlerImpl(securityContext!);
    // } else {
    // securityContext ??=
    //     CertificateService.generateSecurityContext().createSecurityContext();
    // securityContext ??= SecurityContext.defaultContext;
    securityContext ??=
        CertificateService.generateSecurityContext().createSecurityContext();
    if (enforceSecureConnections) {
      _socketHandler = SecureSocketHandler(securityContext!);
    } else {
      _socketHandler = PlainSocketHandler();
    }
    // }
    // }
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
      FtpSession(
        client,
        username: username,
        password: password,
        sharedDirectories: sharedDirectories,
        serverType: serverType,
        startingDirectory: startingDirectory,
        logger: logger,
        secure: enforceSecureConnections,
        secureDataConnection: secureDataConnection,
        secureConnectionAllowed: secureConnectionAllowed,
        securityContext: securityContext,
      );
    }
  }

  Future<void> startInBackground() async {
    await _startServer();
    logger.generalLog('FTP Server is running on port $port');

    _socketHandler.connections.listen((client) {
      logger.generalLog(
          'New client connected from ${client.remoteAddress.address}:${client.remotePort}');
      FtpSession(
        client,
        username: username,
        password: password,
        sharedDirectories: sharedDirectories,
        serverType: serverType,
        startingDirectory: startingDirectory,
        logger: logger,
        secure: enforceSecureConnections,
        secureDataConnection: secureDataConnection,
        secureConnectionAllowed: secureConnectionAllowed,
        securityContext: securityContext,
      );
    });
  }

  Future<void> stop() async {
    _socketHandler.close();
    logger.generalLog('FTP Server stopped');
  }
}
