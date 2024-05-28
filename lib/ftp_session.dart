import 'dart:io';
import 'dart:async';
import 'package:ftp_server/server_type.dart';
import 'package:intl/intl.dart';
import 'ftp_command_handler.dart';
import 'logger_handler.dart';

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
  final List<String> allowedDirectories;
  final String startingDirectory;
  final ServerType serverType;
  final LoggerHandler logger;

  FtpSession(
    this.controlSocket, {
    this.username,
    this.password,
    required this.allowedDirectories,
    required this.startingDirectory,
    required this.serverType,
    required this.logger,
  })  : currentDirectory = startingDirectory,
        commandHandler = FTPCommandHandler(controlSocket, logger) {
    sendResponse('220 Welcome to the FTP server');
    controlSocket.listen(processCommand, onDone: closeConnection);
  }

  bool _isPathAllowed(String path) {
    return allowedDirectories.any((allowedDir) => path.startsWith(allowedDir));
  }

  String _getFullPath(String path) {
    if (path.startsWith('/')) {
      return path;
    }
    return '$currentDirectory/$path';
  }

  void processCommand(List<int> data) {
    String commandLine = String.fromCharCodes(data).trim();
    commandHandler.handleCommand(commandLine, this);
  }

  Future<void> sendResponse(String message) async {
    logger.logResponse(message);
    controlSocket.write("$message\r\n");
  }

  void closeConnection() {
    controlSocket.close();
    dataSocket?.close();
    dataListener?.close();
    print('Connection closed');
  }

  Future<void> enterPassiveMode() async {
    dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    int port = dataListener!.port;
    int p1 = port >> 8;
    int p2 = port & 0xFF;
    String address = controlSocket.address.address.replaceAll('.', ',');
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

  Future<void> listDirectory(String path) async {
    if (dataSocket == null) {
      sendResponse('425 Can\'t open data connection');
      return;
    }

    String fullPath = _getFullPath(path);
    print('Listing directory: $fullPath');

    if (!_isPathAllowed(fullPath)) {
      sendResponse('550 Access denied');
      return;
    }

    Directory dir = Directory(fullPath);
    if (await dir.exists()) {
      List<FileSystemEntity> entities = dir.listSync();
      for (FileSystemEntity entity in entities) {
        var stat = await entity.stat();
        String permissions = _formatPermissions(stat);
        String fileSize = stat.size.toString();
        String modificationTime = _formatModificationTime(stat.modified);
        String fileName = entity.path.split('/').last;
        String entry =
            '$permissions 1 ftp ftp $fileSize $modificationTime $fileName\r\n';
        dataSocket!.write(entry);
      }
      dataSocket!.close();
      dataSocket = null;
      sendResponse('226 Transfer complete');
    } else {
      sendResponse('550 Directory not found $fullPath');
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
    if (dataSocket == null) {
      sendResponse('425 Can\'t open data connection');
      return;
    }

    try {
      String fullPath = _getFullPath(filename);
      if (!_isPathAllowed(fullPath)) {
        sendResponse('550 Access denied');
        return;
      }

      File file = File(fullPath);
      if (await file.exists()) {
        sendResponse('150 Opening data connection');
        Stream<List<int>> fileStream = file.openRead();
        await fileStream.pipe(dataSocket!);
        dataSocket!.close();
        dataSocket = null;
        sendResponse('226 Transfer complete');
      } else {
        sendResponse('550 File not found');
      }
    } catch (e) {
      sendResponse('550 File transfer failed');
      dataSocket = null;
    }
  }

  Future<void> storeFile(String filename) async {
    if (dataSocket == null) {
      sendResponse('425 Can\'t open data connection');
      return;
    }
    String fullPath = _getFullPath(filename);
    if (!_isPathAllowed(fullPath)) {
      sendResponse('550 Access denied');
      return;
    }

    File file = File(fullPath);
    IOSink fileSink = file.openWrite();
    await dataSocket!.listen((data) {
      fileSink.add(data);
    }, onDone: () async {
      await fileSink.close();
      dataSocket!.close();
      dataSocket = null;
      sendResponse('226 Transfer complete');
    }, onError: (error) {
      sendResponse('426 Connection closed; transfer aborted');
      fileSink.close();
    }).asFuture();
  }

  void changeDirectory(String dirname) {
    String fullPath = _getFullPath(dirname);
    if (!_isPathAllowed(fullPath)) {
      sendResponse('550 Access denied');
      return;
    }

    var newDir = Directory(fullPath);
    if (newDir.existsSync()) {
      currentDirectory = newDir.path;
      sendResponse('250 Directory changed to $currentDirectory');
    } else {
      sendResponse('550 Directory not found $fullPath');
    }
  }

  void changeToParentDirectory() {
    var parentDir = Directory(currentDirectory).parent;
    if (_isPathAllowed(parentDir.path) && parentDir.existsSync()) {
      currentDirectory = parentDir.path;
      sendResponse('250 Directory changed to $currentDirectory');
    } else {
      sendResponse('550 Access denied or directory not found');
    }
  }

  void makeDirectory(String dirname) async {
    String newDirPath = _getFullPath(dirname);
    if (!_isPathAllowed(newDirPath)) {
      sendResponse('550 Access denied');
      return;
    }

    var newDir = Directory(newDirPath);
    if (!(await newDir.exists())) {
      await newDir.create();
      sendResponse('257 "$dirname" created');
    } else {
      sendResponse('550 Directory already exists');
    }
  }

  void removeDirectory(String dirname) async {
    String dirPath = _getFullPath(dirname);
    if (!_isPathAllowed(dirPath)) {
      sendResponse('550 Access denied');
      return;
    }

    var dir = Directory(dirPath);
    if (await dir.exists()) {
      await dir.delete();
      sendResponse('250 Directory deleted');
    } else {
      sendResponse('550 Directory not found');
    }
  }

  void deleteFile(String filePath) async {
    String fullPath = _getFullPath(filePath);
    if (!_isPathAllowed(fullPath)) {
      sendResponse('550 Access denied');
      return;
    }

    var file = File(fullPath);
    if (await file.exists()) {
      await file.delete();
      sendResponse('250 File deleted');
    } else {
      sendResponse('550 File not found');
    }
  }

  Future<void> fileSize(String filePath) async {
    String fullPath = _getFullPath(filePath);
    if (!_isPathAllowed(fullPath)) {
      sendResponse('550 Access denied');
      return;
    }

    File file = File(fullPath);
    if (await file.exists()) {
      int size = await file.length();
      sendResponse('213 $size');
    } else {
      sendResponse('550 File not found');
    }
  }
}
