import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:ftp_server/server_type.dart';
import 'package:intl/intl.dart';
import 'ftp_command_handler.dart';
import 'logger_handler.dart';
import 'file_operations/file_operations.dart';

class FtpSession {
  final Socket controlSocket;
  bool isAuthenticated = false;
  final FTPCommandHandler commandHandler;
  ServerSocket? dataListener;
  Socket? dataSocket;
  final String? username;
  final String? password;
  String? cachedUsername;
  final FileOperations fileOperations;
  final ServerType serverType;
  final LoggerHandler logger;

  String get currentDirectory => fileOperations.getCurrentDirectory();

  /// Creates an FTP session with the provided [controlSocket], [fileOperations], and other configurations.
  FtpSession(
    this.controlSocket, {
    this.username,
    this.password,
    required this.fileOperations,
    required this.serverType,
    required this.logger,
  }) : commandHandler = FTPCommandHandler(controlSocket, logger) {
    sendResponse('220 Welcome to the FTP server');
    controlSocket.listen(processCommand, onDone: closeConnection);
  }

  void processCommand(List<int> data) {
    try {
      String commandLine = utf8.decode(data).trim();
      commandHandler.handleCommand(commandLine, this);
    } catch (e) {
      logger.generalLog(e.toString());
      sendResponse('500 Internal server error');
    }
  }

  Future<void> sendResponse(String message) async {
    logger.logResponse(message);
    controlSocket.write("$message\r\n");
  }

  void closeConnection() {
    controlSocket.close();
    dataSocket?.close();
    dataListener?.close();
    logger.generalLog('Connection closed');
  }

  bool openDataConnection() {
    if (dataSocket == null) {
      sendResponse('425 Can\'t open data connection');
      return false;
    }
    sendResponse('150 Opening data connection');
    return true;
  }

  Future<void> enterPassiveMode() async {
    try {
      dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      int port = dataListener!.port;
      int p1 = port >> 8;
      int p2 = port & 0xFF;
      var address = (await _getIpAddress()).replaceAll('.', ',');
      sendResponse('227 Entering Passive Mode ($address,$p1,$p2)');
      dataListener!.first.then((socket) {
        dataSocket = socket;
      });
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
      dataSocket = await Socket.connect(ip, port);
      sendResponse('200 Active mode connection established');
    } catch (e) {
      sendResponse('425 Can\'t enter active mode');
      logger.generalLog('Error entering active mode: $e');
    }
  }

  Future<String> _getIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      logger.generalLog('Error getting IP address: $e');
    }
    return '0.0.0.0';
  }

  Future<void> listDirectory(String path) async {
    try {
      if (!openDataConnection()) {
        return;
      }

      String fullPath = fileOperations.resolvePath(path);
      logger.generalLog('Listing directory: $fullPath');

      if (!fileOperations.exists(fullPath)) {
        sendResponse('550 Directory not found');
        return;
      }

      var dirContents = await fileOperations.listDirectory(fullPath);
      for (var entity in dirContents) {
        var stat = await entity.stat();
        String permissions = _formatPermissions(stat);
        String fileSize = stat.size.toString();
        String modificationTime = _formatModificationTime(stat.modified);
        String fileName = entity.path.split(Platform.pathSeparator).last;
        String entry =
            '$permissions 1 ftp ftp $fileSize $modificationTime $fileName\r\n';
        dataSocket!.write(entry);
      }
      dataSocket!.close();
      dataSocket = null;
      sendResponse('226 Transfer complete');
    } catch (e) {
      sendResponse('550 Failed to list directory');
      logger.generalLog('Error listing directory: $e');
      dataSocket?.close();
      dataSocket = null;
    }
  }

  Future<void> retrieveFile(String filename) async {
    try {
      if (!openDataConnection()) {
        return;
      }

      String fullPath = fileOperations.resolvePath(filename);
      if (!fileOperations.exists(fullPath)) {
        sendResponse('550 File not found');
        return;
      }

      var file = await fileOperations.getFile(fullPath);
      Stream<List<int>> fileStream = file.openRead();
      await fileStream.pipe(dataSocket!);
      dataSocket!.close();
      dataSocket = null;
      sendResponse('226 Transfer complete');
    } catch (e) {
      sendResponse('550 File transfer failed');
      logger.generalLog('Error retrieving file: $e');
      dataSocket?.close();
      dataSocket = null;
    }
  }

  Future<void> storeFile(String filename) async {
    try {
      if (!openDataConnection()) {
        return;
      }
      String fullPath = fileOperations.resolvePath(filename);

      if (!fileOperations.exists(fullPath)) {
        sendResponse('550 Access denied');
        return;
      }

      final directory = Directory(fullPath).parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      var file = File(fullPath);
      var fileSink = file.openWrite();

      dataSocket!.listen(
        (data) {
          fileSink.add(data);
        },
        onDone: () async {
          await fileSink.close();
          await dataSocket!.close();
          dataSocket = null;
          sendResponse('226 Transfer complete');
        },
        onError: (error) async {
          sendResponse('426 Connection closed; transfer aborted');
          await fileSink.close();
          await dataSocket!.close();
          dataSocket = null;
        },
        cancelOnError: true,
      );
    } catch (e) {
      sendResponse('550 Error creating file or directory');
      logger.generalLog('Error storing file: $e');
      dataSocket?.close();
      dataSocket = null;
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
      String newDirPath = fileOperations.resolvePath(dirname);
      if (fileOperations.exists(newDirPath)) {
        sendResponse('550 Directory already exists');
        return;
      }

      await fileOperations.createDirectory(newDirPath);
      sendResponse('257 "$dirname" created');
    } catch (e) {
      sendResponse('550 Failed to create directory');
      logger.generalLog('Error creating directory: $e');
    }
  }

  void removeDirectory(String dirname) async {
    try {
      String dirPath = fileOperations.resolvePath(dirname);
      if (!fileOperations.exists(dirPath)) {
        sendResponse('550 Directory not found');
        return;
      }

      await fileOperations.deleteDirectory(dirPath);
      sendResponse('250 Directory deleted');
    } catch (e) {
      sendResponse('550 Failed to delete directory');
      logger.generalLog('Error deleting directory: $e');
    }
  }

  void deleteFile(String filePath) async {
    try {
      String fullPath = fileOperations.resolvePath(filePath);
      if (!fileOperations.exists(fullPath)) {
        sendResponse('550 File not found');
        return;
      }

      await fileOperations.deleteFile(fullPath);
      sendResponse('250 File deleted');
    } catch (e) {
      sendResponse('550 Failed to delete file');
      logger.generalLog('Error deleting file: $e');
    }
  }

  Future<void> fileSize(String filePath) async {
    try {
      String fullPath = fileOperations.resolvePath(filePath);
      if (!fileOperations.exists(fullPath)) {
        sendResponse('550 File not found');
        return;
      }

      int size = await fileOperations.fileSize(fullPath);
      sendResponse('213 $size');
    } catch (e) {
      sendResponse('550 Failed to get file size');
      logger.generalLog('Error getting file size: $e');
    }
  }

  Future<void> enterExtendedPassiveMode() async {
    try {
      dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      int port = dataListener!.port;
      sendResponse('229 Entering Extended Passive Mode (|||$port|)');
      dataListener!.first.then((socket) {
        dataSocket = socket;
      });
    } catch (e) {
      sendResponse('425 Can\'t enter extended passive mode');
      logger.generalLog('Error entering extended passive mode: $e');
    }
  }

  // Helpers for formatting:
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
}
