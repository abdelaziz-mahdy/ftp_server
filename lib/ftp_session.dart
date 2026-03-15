import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/socket_handler/plain_socket_handler.dart';
import 'package:ftp_server/socket_handler/abstract_socket_handler.dart';
import 'package:ftp_server/socket_wrapper/plain_socket_wrapper.dart';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';
import 'package:intl/intl.dart';
import 'ftp_command_handler.dart';
import 'logger_handler.dart';
import 'file_operations/file_operations.dart';

class FtpSession {
  SocketWrapper controlSocket;
  bool isAuthenticated = false;
  final FTPCommandHandler commandHandler;
  AbstractSocketHandler? dataSocketHandler;
  SocketWrapper? dataSocket;
  final String? username;
  final String? password;
  String? cachedUsername;
  String? pendingRenameFrom;

  final FileOperations fileOperations;
  final ServerType serverType;
  final LoggerHandler logger;
  bool transferInProgress = false;
  Future? _gettingDataSocket;

  /// Whether the control connection is currently secured with TLS.
  bool secure;

  /// The security context used for TLS connections.
  final SecurityContext? securityContext;

  /// Whether the server enforces TLS on all connections (implicit FTPS).
  final bool enforceSecureConnections;

  /// Whether data connections should be secured with TLS.
  /// Can be changed per-session via the PROT command.
  bool secureDataConnection;

  /// Whether the server allows upgrading to TLS via AUTH TLS (explicit FTPS).
  final bool secureConnectionAllowed;

  /// The active subscription on the control socket.
  /// Tracked so it can be cancelled during TLS upgrade.
  StreamSubscription<List<int>>? _controlSubscription;

  /// Creates an FTP session with the provided file operations backend.
  ///
  /// [fileOperations] handles all file/directory logic (virtual, physical, or custom).
  /// [serverType] determines the mode (read-only or read and write).
  /// Optional parameters include [username], [password], and [logger].
  FtpSession(
    this.controlSocket, {
    this.username,
    this.password,
    required FileOperations fileOperations,
    required this.serverType,
    required this.logger,
    this.secure = false,
    this.securityContext,
    this.enforceSecureConnections = false,
    this.secureDataConnection = false,
    this.secureConnectionAllowed = false,
  })  : fileOperations = fileOperations.copy(),
        commandHandler = FTPCommandHandler(logger) {
    sendResponse('220 Welcome to the FTP server');
    logger.generalLog('FtpSession created. Ready to process commands.');
    _listenToControlSocket();
  }

  /// Subscribe to the control socket for incoming commands.
  /// Cancels any existing subscription first.
  void _listenToControlSocket() {
    _controlSubscription?.cancel();
    _controlSubscription =
        controlSocket.listen(processCommand, onDone: closeConnection);
  }

  /// Upgrades the control connection to TLS (called by AUTH TLS handler).
  /// Returns a Future that completes when the TLS handshake is done.
  Future<void> upgradeToTls() async {
    if (controlSocket is! PlainSocketWrapper) {
      throw StateError('Control socket is already secure');
    }

    // PAUSE (don't cancel) the old listener. SecureSocket.secureServer()
    // internally calls _detachRaw() which takes ownership of the existing
    // subscription. If we cancel it, the detach mechanism breaks and the
    // TLS handshake fails. Pausing prevents the old onData handler from
    // receiving TLS ClientHello bytes and misinterpreting them as FTP commands.
    _controlSubscription?.pause();

    // Flush the 234 response before starting the TLS handshake.
    // The client must receive the 234 before it initiates TLS.
    await controlSocket.flush();

    // Perform the TLS handshake. SecureSocket.secureServer internally
    // detaches the raw socket and takes over the paused subscription.
    controlSocket = await (controlSocket as PlainSocketWrapper)
        .upgradeToSecure(securityContext: securityContext!);

    // Ownership of old subscription transferred to SecureSocket internals
    _controlSubscription = null;
    secure = true;

    // Listen on the new secure socket
    _listenToControlSocket();

    logger.generalLog('TLS negotiation completed on control connection');
  }

  void processCommand(List<int> data) {
    try {
      String commandLine = utf8.decode(data).trim();
      commandHandler.handleCommand(commandLine, this);
    } catch (e, s) {
      logger.generalLog(
          "error: $e stack: $s ,input bytes $data, malformed ${utf8.decode(data, allowMalformed: true)}");
      sendResponse('500 Internal server error');
    }
  }

  void sendResponse(String message) {
    logger.logResponse(message);
    try {
      controlSocket.write('$message\r\n');
    } catch (e) {
      logger.generalLog('Error sending response: $e');
    }
  }

  void closeConnection() {
    _controlSubscription?.cancel();
    _controlSubscription = null;
    controlSocket.close();
    dataSocket?.close();
    dataSocketHandler?.close();
    logger.generalLog('Connection closed');
  }

  Future<bool> openDataConnection() async {
    try {
      await _gettingDataSocket;
    } catch (e) {
      logger.generalLog('Error while waiting for data socket: $e');
    }
    if (dataSocket == null) {
      sendResponse('425 Can\'t open data connection');
      return false;
    }
    sendResponse('150 Opening data connection');

    // Per RFC 4217: upgrade data connection to TLS if protection level is Private
    if (secure &&
        securityContext != null &&
        secureDataConnection &&
        dataSocket is PlainSocketWrapper) {
      try {
        dataSocket = await (dataSocket as PlainSocketWrapper)
            .upgradeToSecure(securityContext: securityContext!);
      } catch (e) {
        logger.generalLog('Error upgrading data connection to TLS: $e');
        sendResponse('425 Can\'t establish secure data connection');
        await _closeDataSocket();
        return false;
      }
    }

    return true;
  }

  Future<void> waitForClientDataSocket({Duration? timeout}) async {
    if (dataSocketHandler == null) {
      sendResponse('425 No data connection handler available');
      throw Exception('Data connection handler not initialized');
    }

    var connectionFuture = dataSocketHandler!.connections.first;
    if (timeout != null) {
      connectionFuture = connectionFuture.timeout(timeout, onTimeout: () {
        throw TimeoutException(
            'Timeout reached while waiting for client data socket');
      });
    }

    try {
      var socket = await connectionFuture;
      dataSocket = socket;
    } catch (e) {
      sendResponse('425 Can\'t open data connection: $e');
      logger.generalLog('Error waiting for data socket: $e');
    }
  }

  Future<void> enterPassiveMode() async {
    try {
      dataSocketHandler = PlainSocketHandler();

      await dataSocketHandler!.bind(InternetAddress.anyIPv4, 0);
      int port = dataSocketHandler!.port!;
      int p1 = port >> 8;
      int p2 = port & 0xFF;
      var address = (await _getIpAddress()).replaceAll('.', ',');
      sendResponse('227 Entering Passive Mode ($address,$p1,$p2)');

      _gettingDataSocket =
          waitForClientDataSocket(timeout: Duration(seconds: 30));
    } catch (e) {
      sendResponse('425 Can\'t enter passive mode');
      logger.generalLog('Error entering passive mode: $e');
    }
  }

  Future<void> enterActiveMode(String parameters) async {
    try {
      List<String> parts = parameters.split(',');
      String ip = parts.take(4).join('.');
      int port = int.parse(parts[4]) * 256 + int.parse(parts[5]);

      dataSocket = await PlainSocketWrapper.connect(ip, port);

      sendResponse('200 Active mode connection established');
    } catch (e) {
      sendResponse('425 Can\'t enter active mode');
      logger.generalLog('Error entering active mode: $e');
    }
  }

  Future<String> _getIpAddress() async {
    try {
      final networkInterfaces = await NetworkInterface.list();
      final ipList = networkInterfaces
          .map((interface) => interface.addresses)
          .expand((ip) => ip)
          .where((ip) => ip.type == InternetAddressType.IPv4)
          .toList();

      // Filter IPs that start with '192'
      final wifiIp = ipList.firstWhere(
        (address) => address.address.startsWith('192'),
        orElse: () => ipList.first,
      );

      return wifiIp.address;
    } catch (e) {
      logger.generalLog('Error getting IP address: $e');
    }
    return '0.0.0.0';
  }

  Future<void> listDirectory(String path) async {
    if (!await openDataConnection()) {
      return;
    }

    try {
      transferInProgress = true;

      var dirContents = await fileOperations.listDirectory(path);
      logger.generalLog(
          'Listing directory: $path, for ${fileOperations.resolvePath(path)} dir contents: $dirContents');

      for (FileSystemEntity entity in dirContents) {
        if (!transferInProgress) break; // Abort if transfer is cancelled

        try {
          var stat = await entity.stat();
          String permissions = _formatPermissions(stat);
          String fileSize = stat.size.toString();
          String modificationTime = _formatModificationTime(stat.modified);
          String fileName = entity.path.split(Platform.pathSeparator).last;
          String entry =
              '$permissions 1 ftp ftp $fileSize $modificationTime $fileName\r\n';

          if (dataSocket == null || !transferInProgress) break;

          try {
            dataSocket!.write(entry);
          } catch (socketError) {
            logger.generalLog(
                'Socket write error during directory listing: $socketError');
            transferInProgress = false;
            break;
          }
        } catch (entityError) {
          logger.generalLog(
              'Error processing entity during directory listing: $entityError');
          continue;
        }
      }

      if (transferInProgress) {
        transferInProgress = false;
        await _closeDataSocket();
        sendResponse('226 Transfer complete');
      } else {
        await _closeDataSocket();
        sendResponse('426 Transfer aborted');
      }
    } catch (e) {
      logger.generalLog('Error listing directory: $e');
      sendResponse('550 Failed to list directory');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

  String _formatPermissions(FileStat stat) {
    String type = stat.type == FileSystemEntityType.directory ? 'd' : '-';
    String owner = _permissionToString(stat.mode >> 6);
    String group = _permissionToString((stat.mode >> 3) & 7);
    String others = _permissionToString(stat.mode & 7);
    return '$type$owner$group$others';
  }

  String _permissionToString(int permission) {
    String read = (permission & 4) != 0 ? 'r' : '-';
    String write = (permission & 2) != 0 ? 'w' : '-';
    String execute = (permission & 1) != 0 ? 'x' : '-';
    return '$read$write$execute';
  }

  String _formatModificationTime(DateTime dateTime) {
    return DateFormat('MMM dd HH:mm').format(dateTime);
  }

  Future<void> retrieveFile(String filename) async {
    if (!await openDataConnection()) {
      return;
    }

    try {
      transferInProgress = true;

      if (!fileOperations.exists(filename)) {
        sendResponse('550 File not found $filename');
        transferInProgress = false;
        await _closeDataSocket();
        return;
      }

      String fullPath = fileOperations.resolvePath(filename);
      File file = File(fullPath);

      if (await file.exists()) {
        Stream<List<int>> fileStream = file.openRead();

        StreamSubscription<List<int>>? subscription;
        subscription = fileStream.listen(
          (data) {
            if (transferInProgress && dataSocket != null) {
              try {
                dataSocket!.add(data);
              } catch (e) {
                logger.generalLog('Error writing to data socket: $e');
                transferInProgress = false;
                subscription?.cancel();
                _closeDataSocket();
              }
            }
          },
          onDone: () async {
            if (transferInProgress) {
              transferInProgress = false;
              await _closeDataSocket();
              sendResponse('226 Transfer complete');
            }
          },
          onError: (error) async {
            logger.generalLog('Error reading from file: $error');
            if (transferInProgress) {
              sendResponse('426 Connection closed; transfer aborted');
              transferInProgress = false;
              await _closeDataSocket();
            }
          },
          cancelOnError: true,
        );
      } else {
        sendResponse('550 File not found $fullPath');
        transferInProgress = false;
        await _closeDataSocket();
      }
    } catch (e) {
      logger.generalLog('Exception in retrieveFile: $e');
      sendResponse('550 File transfer failed');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

  Future<void> storeFile(String filename) async {
    if (!await openDataConnection()) {
      return;
    }

    File? file;
    IOSink? fileSink;

    try {
      String fullPath = fileOperations.resolvePath(filename);
      transferInProgress = true;

      // Create the directory if it doesn't exist
      final directory = Directory(fullPath).parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      file = File(fullPath);
      fileSink = file.openWrite();

      dataSocket!.listen(
        (data) {
          if (transferInProgress) {
            try {
              fileSink?.add(data);
            } catch (e) {
              logger.generalLog('Error writing to file: $e');
              _handleTransferError(fileSink);
            }
          }
        },
        onDone: () async {
          if (transferInProgress) {
            try {
              await fileSink?.flush();
              await fileSink?.close();
              transferInProgress = false;
              await _closeDataSocket();
              sendResponse('226 Transfer complete');
              logger
                  .generalLog('File transfer complete: $filename to $fullPath');
            } catch (e) {
              logger.generalLog('Error closing file after transfer: $e');
              _handleTransferError(fileSink);
            }
          }
        },
        onError: (error) async {
          logger.generalLog('Socket error during file upload: $error');
          _handleTransferError(fileSink);
        },
        cancelOnError: true,
      );
    } catch (e) {
      logger.generalLog('Exception in storeFile: $e');
      sendResponse('550 Error creating file or directory: $e');
      transferInProgress = false;
      fileSink
          ?.close()
          .catchError((e) => logger.generalLog('Error closing file sink: $e'));
      await _closeDataSocket();
    }
  }

  void _handleTransferError(IOSink? fileSink) async {
    sendResponse('426 Connection closed; transfer aborted');
    if (fileSink != null) {
      try {
        await fileSink.close();
      } catch (e) {
        logger.generalLog('Error closing file sink during error handling: $e');
      }
    }
    transferInProgress = false;
    await _closeDataSocket();
  }

  Future<void> handleMlsd(String argument, FtpSession session) async {
    if (!await openDataConnection()) {
      return;
    }

    try {
      transferInProgress = true;
      var dirContents = await fileOperations.listDirectory(argument);
      logger.generalLog('Listing directory with MLSD: $argument');

      for (FileSystemEntity entity in dirContents) {
        if (!transferInProgress || dataSocket == null) break;

        try {
          var stat = await entity.stat();
          String facts = _formatMlsdFacts(entity, stat);

          try {
            dataSocket!.write(facts);
          } catch (socketError) {
            logger.generalLog('Socket write error during MLSD: $socketError');
            transferInProgress = false;
            break;
          }
        } catch (entityError) {
          logger
              .generalLog('Error processing entity during MLSD: $entityError');
          continue;
        }
      }

      if (transferInProgress) {
        transferInProgress = false;
        await _closeDataSocket();
        sendResponse('226 Transfer complete.');
      } else {
        await _closeDataSocket();
        sendResponse('426 Transfer aborted');
      }
    } catch (e) {
      logger.generalLog('Error listing directory with MLSD: $e');
      sendResponse('550 Failed to list directory: $e');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

  String _formatMlsdFacts(FileSystemEntity entity, FileStat stat) {
    String type = stat.type == FileSystemEntityType.directory ? "dir" : "file";
    String modify = DateFormat("yyyyMMddHHmmss")
        .format(stat.modified.toUtc()); // Use UTC time
    String size = stat.size.toString();
    String name = entity.path.split(Platform.pathSeparator).last;

    return "type=$type;modify=$modify;size=$size; $name\r\n";
  }

  Future<void> _closeDataSocket() async {
    if (dataSocket != null) {
      try {
        await dataSocket!.flush();
        await dataSocket!.close();
      } catch (e) {
        logger.generalLog('Error closing data socket: $e');
      } finally {
        dataSocket = null;
      }
    }
    dataSocketHandler?.close();
    dataSocketHandler = null;
  }

  void abortTransfer() async {
    if (transferInProgress) {
      transferInProgress = false;
      dataSocket?.destroy();
      sendResponse('426 Transfer aborted');
      dataSocket = null;
    } else {
      sendResponse('226 No transfer in progress');
    }
  }

  void changeDirectory(String dirname) {
    try {
      fileOperations.changeDirectory(dirname);
      sendResponse(
          '250 Directory changed to ${fileOperations.currentDirectory}');
    } catch (e) {
      sendResponse('550 Access denied or directory not found $e');
      logger.generalLog('Error changing directory: $e');
    }
  }

  void changeToParentDirectory() {
    try {
      fileOperations.changeToParentDirectory();
      sendResponse(
          '250 Directory changed to ${fileOperations.currentDirectory}');
    } catch (e) {
      sendResponse('550 Access denied or directory not found $e');
      logger.generalLog('Error changing to parent directory: $e');
    }
  }

  void makeDirectory(String dirname) async {
    try {
      await fileOperations.createDirectory(dirname);
      sendResponse('257 "$dirname" created');
    } catch (e) {
      sendResponse('550 Failed to create directory, error: $e');
      logger.generalLog('Error creating directory: $e');
    }
  }

  void removeDirectory(String dirname) async {
    try {
      await fileOperations.deleteDirectory(dirname);
      sendResponse('250 Directory deleted');
    } catch (e) {
      sendResponse('550 Failed to delete directory $e');
      logger.generalLog('Error deleting directory: $e');
    }
  }

  void deleteFile(String filePath) async {
    try {
      await fileOperations.deleteFile(filePath);
      sendResponse('250 File deleted');
    } catch (e) {
      sendResponse('550 Failed to delete file $e');
      logger.generalLog('Error deleting file: $e');
    }
  }

  Future<void> fileSize(String filePath) async {
    try {
      int size = await fileOperations.fileSize(filePath);
      sendResponse('213 $size');
    } catch (e) {
      sendResponse('550 Failed to get file size');
      logger.generalLog('Error getting file size: $e');
    }
  }

  Future<void> enterExtendedPassiveMode() async {
    try {
      dataSocketHandler = PlainSocketHandler();

      await dataSocketHandler!.bind(InternetAddress.anyIPv4, 0);
      int port = dataSocketHandler!.port!;

      sendResponse('229 Entering Extended Passive Mode (|||$port|)');

      _gettingDataSocket =
          waitForClientDataSocket(timeout: Duration(seconds: 30));
    } catch (e) {
      sendResponse('425 Can\'t enter extended passive mode');
      logger.generalLog('Error entering extended passive mode: $e');
    }
  }

  void handleMdtm(String argument, FtpSession session) {
    try {
      if (!fileOperations.exists(argument)) {
        sendResponse('550 File not found');
        return;
      }

      String fullPath = fileOperations.resolvePath(argument);
      File file = File(fullPath);
      if (file.existsSync()) {
        var stat = file.statSync();
        String modificationTime = _formatMdtmTimestamp(stat.modified);
        sendResponse('213 $modificationTime');
      } else {
        sendResponse('550 File not found');
      }
    } catch (e) {
      sendResponse('550 Could not get modification time: $e');
      logger.generalLog('Error getting modification time: $e');
    }
  }

  String _formatMdtmTimestamp(DateTime dateTime) {
    return DateFormat('yyyyMMddHHmmss').format(dateTime.toUtc());
  }

  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {
    try {
      await fileOperations.renameFileOrDirectory(oldPath, newPath);
      pendingRenameFrom = null;
      sendResponse('250 Requested file action completed successfully');
    } catch (e) {
      pendingRenameFrom = null;
      sendResponse('550 Failed to rename: $e');
      logger.generalLog('Error renaming $oldPath to $newPath: $e');
    }
  }
}
