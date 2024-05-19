import 'package:ftp_server/server_type.dart';

abstract class FtpSession {
  void processCommand(List<int> data);
  void sendResponse(String message);
  void closeConnection();
  void closeControlSocket();
  void setCachedUsername(String username);
  String? getCachedUsername();
  void setAuthenticated(bool isAuthenticated);
  bool isAuthenticated();
  String? getUsername();
  String? getPassword();
  ServerType getServerType();
  void enterPassiveMode();
  void enterActiveMode(String argument);
  void listDirectory(String path);
  void retrieveFile(String filename);
  void storeFile(String filename);
  void changeDirectory(String dirname);
  void changeToParentDirectory();
  void makeDirectory(String dirname);
  void removeDirectory(String dirname);
  void deleteFile(String filePath);
  void fileSize(String filePath);
}
