// lib/file_operations/in_memory_file_operations.dart
import '../file_system/abstract_file_system.dart';
import '../file_system/in_memory_file_system.dart';
import '../session/context/session_context.dart';
import 'abstract_file_operations.dart';

class InMemoryFileOperations implements FileOperations {
  final FtpDirectory rootDirectory;

  InMemoryFileOperations(this.rootDirectory);

  FtpDirectory _findDirectory(String path, FtpDirectory startDir) {
    if (path == '/') {
      return rootDirectory;
    }

    List<String> parts = path.split('/');
    FtpDirectory currentDir = startDir;

    for (String part in parts) {
      if (part.isEmpty) continue;
      var entry = currentDir.listEntries().firstWhere((entry) => entry.name == part);
      if (entry is FtpDirectory) {
        currentDir = entry;
      } else {
        throw Exception('Not a directory');
      }
    }

    return currentDir;
  }

  FtpFile _findFile(String path, FtpDirectory startDir) {
    List<String> parts = path.split('/');
    FtpDirectory currentDir = startDir;

    for (int i = 0; i < parts.length - 1; i++) {
      if (parts[i].isEmpty) continue;
      var entry = currentDir.listEntries().firstWhere((entry) => entry.name == parts[i]);
      if (entry is FtpDirectory) {
        currentDir = entry;
      } else {
        throw Exception('Not a directory');
      }
    }

    var fileEntry = currentDir.listEntries().firstWhere((entry) => entry.name == parts.last);
    if (fileEntry is FtpFile) {
      return fileEntry;
    } else {
      throw Exception('Not a file');
    }
  }

  @override
  Future<void> listDirectory(String path, SessionContext context) async {
    try {
      FtpDirectory dir = _findDirectory(path, rootDirectory);
      for (var entry in dir.listEntries()) {
        context.controlSocket.write('${entry.name}\n');
      }
      context.controlSocket.write('226 Transfer complete\r\n');
    } catch (e) {
      context.controlSocket.write('550 Directory not found\r\n');
    }
  }

  @override
  Future<void> retrieveFile(String filename, SessionContext context) async {
    try {
      FtpFile file = _findFile(filename, rootDirectory);
      List<int> data = file.read();
      context.dataSocket?.add(data);
      context.dataSocket?.close();
      context.controlSocket.write('226 Transfer complete\r\n');
    } catch (e) {
      context.controlSocket.write('550 File not found\r\n');
    }
  }

  @override
  Future<void> storeFile(String filename, SessionContext context) async {
    try {
      FtpDirectory dir = _findDirectory(context.currentDirectory, rootDirectory);
      List<int> data = await context.dataSocket!.fold([], (buffer, data) => buffer..addAll(data));
      var file = InMemoryFtpFile(filename, DateTime.now(), data);
      dir.addEntry(file);
      context.controlSocket.write('226 Transfer complete\r\n');
    } catch (e) {
      context.controlSocket.write('550 Could not store file\r\n');
    }
  }

  @override
  Future<void> changeDirectory(String dirname, SessionContext context) async {
    try {
      FtpDirectory dir = _findDirectory(dirname, rootDirectory);
      context.currentDirectory = dir.name;
      context.controlSocket.write('250 Directory successfully changed\r\n');
    } catch (e) {
      context.controlSocket.write('550 Directory not found\r\n');
    }
  }

  @override
  Future<void> makeDirectory(String dirname, SessionContext context) async {
    try {
      FtpDirectory dir = _findDirectory(context.currentDirectory, rootDirectory);
      dir.addEntry(InMemoryFtpDirectory(dirname));
      context.controlSocket.write('257 Directory created\r\n');
    } catch (e) {
      context.controlSocket.write('550 Could not create directory\r\n');
    }
  }

  @override
  Future<void> removeDirectory(String dirname, SessionContext context) async {
    try {
      FtpDirectory dir = _findDirectory(context.currentDirectory, rootDirectory);
      dir.removeEntry(dirname);
      context.controlSocket.write('250 Directory removed\r\n');
    } catch (e) {
      context.controlSocket.write('550 Could not remove directory\r\n');
    }
  }

  @override
  Future<void> deleteFile(String filePath, SessionContext context) async {
    try {
      FtpDirectory dir = _findDirectory(context.currentDirectory, rootDirectory);
      dir.removeEntry(filePath);
      context.controlSocket.write('250 File deleted\r\n');
    } catch (e) {
      context.controlSocket.write('550 Could not delete file\r\n');
    }
  }

  @override
  Future<void> fileSize(String filePath, SessionContext context) async {
    try {
      FtpFile file = _findFile(filePath, rootDirectory);
      context.controlSocket.write('213 ${file.size}\r\n');
    } catch (e) {
      context.controlSocket.write('550 File not found\r\n');
    }
  }

  @override
  Future<void> rename(String from, String to, SessionContext context) async {
    try {
      FtpDirectory dir = _findDirectory(context.currentDirectory, rootDirectory);
      var entry = dir.listEntries().firstWhere((entry) => entry.name == from);
      dir.removeEntry(from);
      entry = (entry is FtpFile)
          ? InMemoryFtpFile(to, entry.lastModified, entry.read())
          : InMemoryFtpDirectory(to);
      dir.addEntry(entry);
      context.controlSocket.write('250 Rename successful\r\n');
    } catch (e) {
      context.controlSocket.write('550 Could not rename file\r\n');
    }
  }

  @override
  Future<void> storeUnique(String filename, SessionContext context) async {
    try {
      FtpDirectory dir = _findDirectory(context.currentDirectory, rootDirectory);
      List<int> data = await context.dataSocket!.fold([], (buffer, data) => buffer..addAll(data));
      String uniqueFilename = '${filename}_${DateTime.now().millisecondsSinceEpoch}';
      var file = InMemoryFtpFile(uniqueFilename, DateTime.now(), data);
      dir.addEntry(file);
      context.controlSocket.write('226 Transfer complete\r\n');
    } catch (e) {
      context.controlSocket.write('550 Could not store file\r\n');
    }
  }
}
