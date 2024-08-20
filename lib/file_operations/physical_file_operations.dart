import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_operations.dart';

/// Implementation of [FileOperations] for interacting with the physical file system.
class PhysicalFileOperations implements FileOperations {
  final String rootDirectory;
  String _currentDirectory;

  /// Creates an instance of [PhysicalFileOperations] with the given root directory.
  PhysicalFileOperations(this.rootDirectory) : _currentDirectory = rootDirectory;

  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    final fullPath = resolvePath(path);
    final dir = Directory(fullPath);
    return dir.listSync();
  }

  @override
  Future<File> getFile(String path) async {
    final fullPath = resolvePath(path);
    return File(fullPath);
  }

  @override
  Future<void> writeFile(String path, List<int> data) async {
    final fullPath = resolvePath(path);
    final file = File(fullPath);
    await file.writeAsBytes(data);
  }

  @override
  Future<List<int>> readFile(String path) async {
    final file = await getFile(path);
    return file.readAsBytes();
  }

  @override
  Future<void> createDirectory(String path) async {
    final fullPath = resolvePath(path);
    final dir = Directory(fullPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = await getFile(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> deleteDirectory(String path) async {
    final dir = Directory(resolvePath(path));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<int> fileSize(String path) async {
    final file = await getFile(path);
    return await file.length();
  }

  @override
  bool exists(String path) {
    final fullPath = resolvePath(path);
    return File(fullPath).existsSync() || Directory(fullPath).existsSync();
  }

  @override
  String resolvePath(String path) {
    return p.normalize(p.join(_currentDirectory, path));
  }

  @override
  String getCurrentDirectory() {
    return _currentDirectory;
  }

  @override
  void changeDirectory(String path) {
    final fullPath = resolvePath(path);
    if (Directory(fullPath).existsSync()) {
      _currentDirectory = fullPath;
    } else {
      throw FileSystemException("Directory not found", fullPath);
    }
  }

  @override
  void changeToParentDirectory() {
    final parentDir = Directory(_currentDirectory).parent;
    if (parentDir.existsSync()) {
      _currentDirectory = parentDir.path;
    } else {
      throw FileSystemException("Parent directory not found", parentDir.path);
    }
  }
}
