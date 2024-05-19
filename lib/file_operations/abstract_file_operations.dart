import '../session/context/session_context.dart';

abstract class FileOperations {
  Future<void> listDirectory(String path, SessionContext context);
  Future<void> retrieveFile(String filename, SessionContext context);
  Future<void> storeFile(String filename, SessionContext context);
  Future<void> changeDirectory(String dirname, SessionContext context);
  Future<void> makeDirectory(String dirname, SessionContext context);
  Future<void> removeDirectory(String dirname, SessionContext context);
  Future<void> deleteFile(String filePath, SessionContext context);
  Future<void> fileSize(String filePath, SessionContext context);
  Future<void> rename(String from, String to, SessionContext context);
  Future<void> storeUnique(String filename, SessionContext context);
}
