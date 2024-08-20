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
  String currentDirectory;
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

  /// Creates an FTP session with the provided [controlSocket], [fileOperations], and other configurations.
  FtpSession(
    this.controlSocket, {
    this.username,
    this.password,
    required this.fileOperations,
    required this.serverType,
    required this.logger,
  })  : currentDirectory = '/',
        commandHandler = FTPCommandHandler(controlSocket, logger) {
    sendResponse('220 Welcome to the FTP server');
    controlSocket.listen(processCommand, onDone: closeConnection);
  }

  void processCommand(List<int> data) {
    try {
      String commandLine = utf8.decode(data).trim();
      commandHandler.handleCommand(commandLine, this);
    } catch (e) {
      logger.generalLog(e.toString());
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
    dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    int port = dataListener!.port;
    int p1 = port >> 8;
    int p2 = port & 0xFF;
    var address = (await _getIpAddress()).replaceAll('.', ',');
    sendResponse('227 Entering Passive Mode ($address,$p1,$p2)');
    dataListener!.first.then((socket) {
      dataSocket = socket;
    });
  }

  Future<void> enterActiveMode(String parameters) async {
    List<String> parts = parameters.split(',');
    String ip = parts.take(4).join('.');
    int port = int.parse(parts[4]) * 256 + int.parse(parts[5]);
    dataSocket = await Socket.connect(ip, port);
    sendResponse('200 Active mode connection established');
  }

  Future<String> _getIpAddress() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return '0.0.0.0';
  }

  Future<void> listDirectory(String path) async {
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
  }

  Future<void> retrieveFile(String filename) async {
    if (!openDataConnection()) {
      return;
    }

    try {
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
      dataSocket = null;
    }
  }

  Future<void> storeFile(String filename) async {
    if (!openDataConnection()) {
      return;
    }
    String fullPath = fileOperations.resolvePath(filename);

    if (!fileOperations.exists(fullPath)) {
      sendResponse('550 Access denied');
      return;
    }

    try {
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
      sendResponse('550 Error creating file or directory $e');
      dataSocket = null;
    }
  }

  void changeDirectory(String dirname) {
    String fullPath = fileOperations.resolvePath(dirname);
    if (!fileOperations.exists(fullPath)) {
      sendResponse('550 Directory not found');
      return;
    }

    currentDirectory = fullPath;
    sendResponse('250 Directory changed to $currentDirectory');
  }

  void changeToParentDirectory() {
    var parentDir = Directory(currentDirectory).parent;
    if (fileOperations.exists(parentDir.path)) {
      currentDirectory = parentDir.path;
      sendResponse('250 Directory changed to $currentDirectory');
    } else {
      sendResponse('550 Access denied or directory not found');
    }
  }

  void makeDirectory(String dirname) async {
    String newDirPath = fileOperations.resolvePath(dirname);
    if (fileOperations.exists(newDirPath)) {
      sendResponse('550 Directory already exists');
      return;
    }

    await fileOperations.createDirectory(newDirPath);
    sendResponse('257 "$dirname" created');
  }

  void removeDirectory(String dirname) async {
    String dirPath = fileOperations.resolvePath(dirname);
    if (!fileOperations.exists(dirPath)) {
      sendResponse('550 Directory not found');
      return;
    }

    await fileOperations.deleteDirectory(dirPath);
    sendResponse('250 Directory deleted');
  }

  void deleteFile(String filePath) async {
    String fullPath = fileOperations.resolvePath(filePath);
    if (!fileOperations.exists(fullPath)) {
      sendResponse('550 File not found');
      return;
    }

    await fileOperations.deleteFile(fullPath);
    sendResponse('250 File deleted');
  }

  Future<void> fileSize(String filePath) async {
    String fullPath = fileOperations.resolvePath(filePath);
    if (!fileOperations.exists(fullPath)) {
      sendResponse('550 File not found');
      return;
    }

    int size = await fileOperations.fileSize(fullPath);
    sendResponse('213 $size');
  }

  Future<void> enterExtendedPassiveMode() async {
    dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    int port = dataListener!.port;
    sendResponse('229 Entering Extended Passive Mode (|||$port|)');
    dataListener!.first.then((socket) {
      dataSocket = socket;
    });
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
