// lib/ftp_session.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:ftp_server/socket_handler/plain_socket_handler.dart';
import 'package:ftp_server/socket_handler/secure_socket_handler.dart';
import 'package:ftp_server/socket_handler/abstract_socket_handler.dart';
import 'package:ftp_server/socket_wrapper/plain_socket_wrapper.dart';
import 'package:ftp_server/socket_wrapper/secure_socket_wrapper.dart';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';

import 'file_operations/virtual_file_operations.dart';
import 'server_type.dart';
import 'ftp_command_handler.dart';
import 'logger_handler.dart';
import 'file_operations/file_operations.dart';
import 'package:intl/intl.dart';

class FtpSession {
  SocketWrapper controlSocket;
  bool isAuthenticated = false;
  final FTPCommandHandler commandHandler;
  AbstractSocketHandler? dataSocketHandler;
  SocketWrapper? dataSocket;
  final String? username;
  final String? password;
  String? cachedUsername;

  final FileOperations fileOperations;
  final List<String> sharedDirectories;
  final ServerType serverType;
  final LoggerHandler logger;
  bool transferInProgress = false;
  Future? _gettingDataSocket;
  String get currentDirectory => fileOperations.getCurrentDirectory();

  bool secure;
  final SecurityContext? securityContext;

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

  // this is not currently used
  // String? dataChannelProtectionLevel;
  FtpSession(
    this.controlSocket, {
    this.username,
    this.password,
    required this.sharedDirectories,
    required this.serverType,
    required this.logger,
    String? startingDirectory,
    this.secure = true,
    this.securityContext,
    this.enforceSecureConnections = false,
    this.secureDataConnection = false,
    this.secureConnectionAllowed = false,
  })  : commandHandler = FTPCommandHandler(controlSocket, logger),
        fileOperations = VirtualFileOperations(sharedDirectories) {
    sendResponse('220 Welcome to the FTP server');

    // Set the starting directory if provided
    if (startingDirectory != null && fileOperations.exists(startingDirectory)) {
      try {
        fileOperations.changeDirectory(startingDirectory);
      } catch (e) {
        logger.generalLog('Failed to set starting directory: $e');
        sendResponse('550 Failed to set starting directory');
      }
    }

    listenToControlMessages();
  }

  void listenToControlMessages() {
    controlSocket.listen(processCommand, onDone: closeConnection);
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
    controlSocket.write("$message\r\n");
  }

  void closeConnection() {
    controlSocket.close();
    dataSocket?.close();
    dataSocketHandler?.close();
    logger.generalLog('Connection closed');
  }

  Future<bool> openDataConnection() async {
    await _gettingDataSocket;
    if (dataSocket == null) {
      sendResponse('425 Can\'t open data connection');
      return false;
    }
    sendResponse('150 Opening data connection');

    // if (secure &&
    //     securityContext != null &&
    //     secureDataConnection &&
    //     dataSocket is PlainSocketWrapper) {
    //   dataSocket = await (dataSocket as PlainSocketWrapper)
    //       .upgradeToSecure(securityContext: securityContext!);
    // }

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
      // Initialize the appropriate SocketHandler for data connection
      if (secure) {
        if (securityContext == null) {
          sendResponse('500 Server misconfiguration');
          return;
        }
        dataSocketHandler = SecureSocketHandler(securityContext!);
      } else {
        dataSocketHandler = PlainSocketHandler();
      }
      // dataSocketHandler = PlainSocketHandler();

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

      if (secure) {
        dataSocket = await SecureSocketWrapper.connect(ip, port,
            securityContext: securityContext!);
      } else {
        dataSocket = await PlainSocketWrapper.connect(ip, port);
      }

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
      logger
          .generalLog('Listing directory: ${fileOperations.resolvePath(path)}');

      for (FileSystemEntity entity in dirContents) {
        if (!transferInProgress) break; // Abort if transfer is cancelled

        var stat = await entity.stat();
        String permissions = _formatPermissions(stat);
        String fileSize = stat.size.toString();
        String modificationTime = _formatModificationTime(stat.modified);
        String fileName = entity.path.split(Platform.pathSeparator).last;
        String entry =
            '$permissions 1 ftp ftp $fileSize $modificationTime $fileName\r\n';

        dataSocket!.write(entry);
      }

      if (transferInProgress) {
        transferInProgress = false;
        await _closeDataSocket();
        sendResponse('226 Transfer complete');
      }
    } catch (e) {
      sendResponse('550 Failed to list directory');
      logger.generalLog('Error listing directory: $e');
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
        return;
      }

      String fullPath = fileOperations.resolvePath(filename);
      File file = File(fullPath);

      if (await file.exists()) {
        Stream<List<int>> fileStream = file.openRead();
        fileStream.listen(
          (data) {
            if (transferInProgress) {
              dataSocket?.add(data);
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
      }
    } catch (e) {
      sendResponse('550 File transfer failed');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

  Future<void> storeFile(String filename) async {
    if (!await openDataConnection()) {
      return;
    }

    try {
      String fullPath = fileOperations.resolvePath(filename);

      transferInProgress = true;

      // Create the directory if it doesn't exist
      final directory = Directory(fullPath).parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      File file = File(fullPath);
      IOSink fileSink = file.openWrite();

      dataSocket!.listen(
        (data) {
          if (transferInProgress) {
            fileSink.add(data);
          }
        },
        onDone: () async {
          if (transferInProgress) {
            await fileSink.close();
            transferInProgress = false;
            await _closeDataSocket();
            sendResponse('226 Transfer complete');
          }
        },
        onError: (error) async {
          if (transferInProgress) {
            sendResponse('426 Connection closed; transfer aborted');
            await fileSink.close();
            transferInProgress = false;
            await _closeDataSocket();
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      sendResponse('550 Error creating file or directory: $e');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

  Future<void> handleMlsd(String argument, FtpSession session) async {
    if (!await session.openDataConnection()) {
      return;
    }

    try {
      session.transferInProgress = true;
      var dirContents = await session.fileOperations.listDirectory(argument);
      logger.generalLog('Listing directory with MLSD: $argument');

      for (FileSystemEntity entity in dirContents) {
        if (!session.transferInProgress) break;
        var stat = await entity.stat();
        String facts = _formatMlsdFacts(entity, stat);
        dataSocket!.write(facts);
      }

      if (session.transferInProgress) {
        session.transferInProgress = false;
        await session._closeDataSocket();
        session.sendResponse('226 Transfer complete.');
      }
    } catch (e) {
      session.sendResponse('550 Failed to list directory: $e');
      logger.generalLog('Error listing directory with MLSD: $e');
      session.transferInProgress = false;
      await session._closeDataSocket();
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

  /// Close the data socket and associated handler.
  ///
  /// This function is intended to be private.
  Future<void> _closeDataSocket() async {
    await dataSocket?.flush();
    await dataSocket?.close();
    dataSocket = null;
    dataSocketHandler?.close();
    dataSocketHandler = null;
  }

  void abortTransfer() async {
    if (transferInProgress) {
      transferInProgress = false;

      await dataSocket?.close();

      sendResponse('426 Transfer aborted');
      await _closeDataSocket();
    } else {
      sendResponse('226 No transfer in progress');
    }
  }

  void changeDirectory(String dirname) {
    try {
      fileOperations.changeDirectory(dirname);
      sendResponse('250 Directory changed to $currentDirectory');
    } catch (e) {
      sendResponse('550 Access denied or directory not found $e');
      logger.generalLog('Error changing directory: $e');
    }
  }

  void changeToParentDirectory() {
    try {
      fileOperations.changeToParentDirectory();
      sendResponse('250 Directory changed to $currentDirectory');
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
      // Initialize the appropriate SocketHandler for data connection
      if (secure) {
        if (securityContext == null) {
          sendResponse('500 Server misconfiguration');
          return;
        }
        dataSocketHandler = SecureSocketHandler(securityContext!);
      } else {
        dataSocketHandler = PlainSocketHandler();
      }

      // dataSocketHandler = PlainSocketHandler();

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
}
