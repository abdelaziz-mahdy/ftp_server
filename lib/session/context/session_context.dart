import 'dart:io';
import 'package:ftp_server/server_type.dart';

class SessionContext {
  final Socket controlSocket;
  String currentDirectory;
  bool isAuthenticated = false;
  ServerSocket? dataListener;
  Socket? dataSocket;
  final String? username;
  final String? password;
  String? cachedUsername;
  final List<String> allowedDirectories;
  final String startingDirectory;
  final ServerType serverType;

  SessionContext({
    required this.controlSocket,
    required this.currentDirectory,
    required this.allowedDirectories,
    required this.startingDirectory,
    required this.serverType,
    this.username,
    this.password,
  });
}
