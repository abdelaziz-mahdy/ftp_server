import 'dart:io';
import 'dart:async';

import 'package:ftp_server/server_type.dart';

import '../command_handler/abstract_command_handler.dart';
import '../file_operations/abstract_file_operations.dart';
import 'abstract_session.dart';
import 'context/session_context.dart';

class ConcreteFtpSession implements FtpSession {
  final SessionContext context;
  final CommandHandler commandHandler;
  final FileOperations fileOperations;

  ConcreteFtpSession(
    this.context, {
    required this.commandHandler,
    required this.fileOperations,
  }) {
    sendResponse('220 Welcome to the FTP server');
    context.controlSocket.listen(processCommand, onDone: closeConnection);
  }

  @override
  void processCommand(List<int> data) {
    String commandLine = String.fromCharCodes(data).trim();
    commandHandler.handleCommand(commandLine, this);
  }

  @override
  void sendResponse(String message) {
    context.controlSocket.write("$message\r\n");
  }

  @override
  void closeConnection() {
    context.controlSocket.close();
    context.dataSocket?.close();
    context.dataListener?.close();
    print('Connection closed');
  }

  @override
  void closeControlSocket() {
    context.controlSocket.close();
  }

  @override
  void setCachedUsername(String username) {
    context.cachedUsername = username;
  }

  @override
  String? getCachedUsername() {
    return context.cachedUsername;
  }

  @override
  void setAuthenticated(bool isAuthenticated) {
    context.isAuthenticated = isAuthenticated;
  }

  @override
  bool isAuthenticated() {
    return context.isAuthenticated;
  }

  @override
  String? getUsername() {
    return context.username;
  }

  @override
  String? getPassword() {
    return context.password;
  }

  @override
  ServerType getServerType() {
    return context.serverType;
  }

  @override
  Future<void> enterPassiveMode() async {
    context.dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    int port = context.dataListener!.port;
    int p1 = port >> 8;
    int p2 = port & 0xFF;
    String address = context.controlSocket.address.address.replaceAll('.', ',');
    sendResponse('227 Entering Passive Mode ($address,$p1,$p2)');
    context.dataListener!.first.then((socket) {
      context.dataSocket = socket;
    });
  }

  @override
  Future<void> enterActiveMode(String parameters) async {
    List<String> parts = parameters.split(',');
    String ip = parts.take(4).join('.');
    int port = int.parse(parts[4]) * 256 + int.parse(parts[5]);
    context.dataSocket = await Socket.connect(ip, port);
    sendResponse('200 Active mode connection established');
  }

  @override
  void listDirectory(String path, {bool isMachineReadable = false}) {
    fileOperations.listDirectory(path, context);
  }

  @override
  void retrieveFile(String filename) {
    fileOperations.retrieveFile(filename, context);
  }

  @override
  void storeFile(String filename) {
    fileOperations.storeFile(filename, context);
  }

  @override
  void changeDirectory(String dirname) {
    fileOperations.changeDirectory(dirname, context);
  }

  @override
  Future<void> changeToParentDirectory() async {
    var parentDir = Directory(context.currentDirectory).parent;
    if (_isPathAllowed(parentDir.path, context.allowedDirectories) &&
        parentDir.existsSync()) {
      context.currentDirectory = parentDir.path;
      sendResponse('250 Directory changed to ${context.currentDirectory}');
    } else {
      sendResponse('550 Access denied or directory not found');
    }
  }

  @override
  void makeDirectory(String dirname) {
    fileOperations.makeDirectory(dirname, context);
  }

  @override
  void removeDirectory(String dirname) {
    fileOperations.removeDirectory(dirname, context);
  }

  @override
  void deleteFile(String filePath) {
    fileOperations.deleteFile(filePath, context);
  }

  @override
  void fileSize(String filePath) {
    fileOperations.fileSize(filePath, context);
  }

  @override
  void reinitialize() {
    context.isAuthenticated = false;
    context.cachedUsername = null;
    sendResponse('220 Service ready for new user');
  }

  @override
  void abort() {
    context.dataSocket?.destroy();
    sendResponse('426 Connection closed; transfer aborted');
  }

  @override
  void renameFrom(String from) {
    context.cachedUsername =
        from; // Using cachedUsername temporarily to store "from" filename
    sendResponse('350 Requested file action pending further information');
  }

  @override
  void renameTo(String to) {
    if (context.cachedUsername == null) {
      sendResponse('503 Bad sequence of commands');
      return;
    }
    fileOperations.rename(context.cachedUsername!, to, context);
    context.cachedUsername = null;
  }

  @override
  void restart(String marker) {
    //TODO: Restart functionality is often implemented using custom logic and file operations support for partial reads/writes
    sendResponse(
        '350 Restarting at marker $marker. Send STORE or RETRIEVE to initiate transfer');
  }

  @override
  void storeUnique(String filename) {
    String uniqueFilename = _generateUniqueFilename(filename);
    storeFile(uniqueFilename);
  }

  @override
  void listSingle(String filename) {
    fileOperations.listDirectory(filename, context);
  }

  @override
  void printWorkingDirectory() {
    sendResponse('257 "${context.currentDirectory}" is the current directory');
  }

  @override
  void setOptions(String options) {
    //TODO: Implement options logic
    sendResponse('200 Command okay');
  }

  @override
  void setHost(String host) {
    //TODO: Implement host logic
    sendResponse('200 Command okay');
  }

  @override
  void modifyTime(String filename) {
    //TODO: Implement modify time logic
    sendResponse('213 Modification time is [timestamp]');
  }

  @override
  void featureList() {
    sendResponse('211-Features:\r\n PASV\r\n SIZE\r\n MDTM\r\n211 End');
  }

  @override
  void systemStatus() {
    sendResponse('211 System status ok');
  }

  @override
  void authenticate(String mechanism) {
    //TODO: Implement authenticate logic
    sendResponse('334 Authentication mechanism accepted');
  }

  bool _isPathAllowed(String path, List<String> allowedDirectories) {
    return allowedDirectories.any((allowedDir) => path.startsWith(allowedDir));
  }

  String _generateUniqueFilename(String filename) {
    // Generate a unique filename by appending a timestamp or UUID
    String uniqueSuffix = DateTime.now().millisecondsSinceEpoch.toString();
    return '$filename.$uniqueSuffix';
  }
}
