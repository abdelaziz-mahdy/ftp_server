import 'dart:io';
import 'dart:async';

import 'package:ftp_server/server_type.dart';
import 'package:intl/intl.dart';

import '../command_handler/abstract_command_handler.dart';
import '../file_operations/abstract_file_operations.dart';
import 'abstract_session.dart';
import 'context/session_context.dart';

import 'dart:io';
import 'dart:async';
import 'package:ftp_server/server_type.dart';
import 'package:intl/intl.dart';

import 'abstract_session.dart';
import 'context/session_context.dart';
import 'dart:io';
import 'dart:async';
import 'package:ftp_server/server_type.dart';
import 'package:intl/intl.dart';
import 'package:ftp_server/command_handler/abstract_command_handler.dart';
import 'package:ftp_server/file_operations/abstract_file_operations.dart';
import 'package:ftp_server/session/abstract_session.dart';
import 'package:ftp_server/session/context/session_context.dart';

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
  void listDirectory(String path) {
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
    if (_isPathAllowed(parentDir.path, context.allowedDirectories) && parentDir.existsSync()) {
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

  bool _isPathAllowed(String path, List<String> allowedDirectories) {
    return allowedDirectories.any((allowedDir) => path.startsWith(allowedDir));
  }
}
