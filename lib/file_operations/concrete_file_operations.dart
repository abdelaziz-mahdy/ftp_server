import 'dart:io';
import 'package:intl/intl.dart';
import '../session/abstract_session.dart';
import '../session/context/session_context.dart';
import 'abstract_file_operations.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'abstract_file_operations.dart';

class ConcreteFileOperations implements FileOperations {
  @override
  Future<void> listDirectory(String path, SessionContext context) async {
    if (context.dataSocket == null) {
      context.controlSocket.write('425 Can\'t open data connection\r\n');
      return;
    }

    String fullPath = context.currentDirectory + (path.isEmpty ? '' : '/$path');
    if (!_isPathAllowed(fullPath, context.allowedDirectories)) {
      context.controlSocket.write('550 Access denied\r\n');
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
        String fileName = entity.path.replaceFirst('${dir.path}/', '');
        String entry =
            '$permissions 1 ftp ftp $fileSize $modificationTime $fileName\r\n';
        context.dataSocket!.write(entry);
      }
      context.dataSocket!.close();
      context.dataSocket = null;
      context.controlSocket.write('226 Transfer complete\r\n');
    } else {
      context.controlSocket.write('550 Directory not found\r\n');
    }
  }

  @override
  Future<void> retrieveFile(String filename, SessionContext context) async {
    if (context.dataSocket == null) {
      context.controlSocket.write('425 Can\'t open data connection\r\n');
      return;
    }

    try {
      String fullPath = filename;
      if (!_isPathAllowed(fullPath, context.allowedDirectories)) {
        context.controlSocket.write('550 Access denied\r\n');
        return;
      }

      File file = File(fullPath);
      if (await file.exists()) {
        context.controlSocket.write('150 Sending file\r\n');
        Stream<List<int>> fileStream = file.openRead();
        await fileStream.pipe(context.dataSocket!);
        await context.dataSocket!.flush();
        context.dataSocket!.close();
        context.dataSocket = null;
        context.controlSocket.write('226 Transfer complete\r\n');
      } else {
        context.controlSocket.write('550 File not found\r\n');
      }
    } catch (e) {
      context.controlSocket.write('550 File transfer failed\r\n');
      if (context.dataSocket != null) {
        context.dataSocket = null;
      }
    }
  }

  @override
  Future<void> storeFile(String filename, SessionContext context) async {
    if (context.dataSocket == null) {
      context.controlSocket.write('425 Can\'t open data connection\r\n');
      return;
    }

    String fullPath = filename;
    if (!_isPathAllowed(fullPath, context.allowedDirectories)) {
      context.controlSocket.write('550 Access denied\r\n');
      return;
    }

    File file = File(fullPath);
    IOSink fileSink = file.openWrite();
    await context.dataSocket!.listen((data) {
      fileSink.add(data);
    }, onDone: () async {
      await fileSink.close();
      context.dataSocket!.close();
      context.dataSocket = null;
      context.controlSocket.write('226 Transfer complete\r\n');
    }, onError: (error) {
      context.controlSocket
          .write('426 Connection closed; transfer aborted\r\n');
      fileSink.close();
    }).asFuture();
  }

  @override
  Future<void> changeDirectory(String dirname, SessionContext context) async {
    String newDirPath = dirname;
    if (!_isPathAllowed(newDirPath, context.allowedDirectories)) {
      context.controlSocket.write('550 Access denied\r\n');
      return;
    }

    var newDir = Directory(newDirPath);
    if (newDir.existsSync()) {
      context.currentDirectory = newDir.path;
      context.controlSocket
          .write('250 Directory changed to ${context.currentDirectory}\r\n');
    } else {
      context.controlSocket.write('550 Directory not found\r\n');
    }
  }

  @override
  Future<void> makeDirectory(String dirname, SessionContext context) async {
    String newDirPath = '${context.currentDirectory}/$dirname';
    if (!_isPathAllowed(newDirPath, context.allowedDirectories)) {
      context.controlSocket.write('550 Access denied\r\n');
      return;
    }

    var newDir = Directory(newDirPath);
    if (!(await newDir.exists())) {
      await newDir.create();
      context.controlSocket.write('257 "$dirname" created\r\n');
    } else {
      context.controlSocket.write('550 Directory already exists\r\n');
    }
  }

  @override
  Future<void> removeDirectory(String dirname, SessionContext context) async {
    String dirPath = '${context.currentDirectory}/$dirname';
    if (!_isPathAllowed(dirPath, context.allowedDirectories)) {
      context.controlSocket.write('550 Access denied\r\n');
      return;
    }

    var dir = Directory(dirPath);
    if (await dir.exists()) {
      await dir.delete();
      context.controlSocket.write('250 Directory deleted\r\n');
    } else {
      context.controlSocket.write('550 Directory not found\r\n');
    }
  }

  @override
  Future<void> deleteFile(String filePath, SessionContext context) async {
    String fullPath = filePath;
    if (!_isPathAllowed(fullPath, context.allowedDirectories)) {
      context.controlSocket.write('550 Access denied\r\n');
      return;
    }

    var file = File(fullPath);
    if (await file.exists()) {
      await file.delete();
      context.controlSocket.write('250 File deleted\r\n');
    } else {
      context.controlSocket.write('550 File not found\r\n');
    }
  }

  @override
  Future<void> fileSize(String filePath, SessionContext context) async {
    String fullPath = filePath;
    if (!_isPathAllowed(fullPath, context.allowedDirectories)) {
      context.controlSocket.write('550 Access denied\r\n');
      return;
    }

    File file = File(fullPath);
    if (await file.exists()) {
      int size = await file.length();
      context.controlSocket.write('213 $size\r\n');
    } else {
      context.controlSocket.write('550 File not found\r\n');
    }
  }

  bool _isPathAllowed(String path, List<String> allowedDirectories) {
    return allowedDirectories.any((allowedDir) => path.startsWith(allowedDir));
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
}
