import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_operations.dart';

/// Implementation of [FileOperations] for managing a virtual file system that maps to physical directories.
class VirtualFileOperations implements FileOperations {
  final List<String> allowedDirectories;
  String _currentDirectory;

  /// Creates an instance of [VirtualFileOperations] with the given allowed directories.
  VirtualFileOperations(this.allowedDirectories)
      : _currentDirectory =
            allowedDirectories.isNotEmpty ? allowedDirectories[0] : '/';

  String _mapVirtualToPhysicalPath(String virtualPath) {
    virtualPath =
        virtualPath.startsWith('/') ? virtualPath.substring(1) : virtualPath;

    for (var dir in allowedDirectories) {
      if (virtualPath.isEmpty || virtualPath.startsWith(dir.split('/').last)) {
        String relativePath =
            virtualPath.isEmpty ? '' : virtualPath.split('/').skip(1).join('/');
        return p.normalize(p.join(dir, relativePath));
      }
    }

    return allowedDirectories.first;
  }

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
    return _mapVirtualToPhysicalPath(path);
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
    if (_currentDirectory == "/") {
      throw Exception(
        "Parent directory is above root ${parentDir.path}",
      );
    }
    if (parentDir.existsSync()) {
      _currentDirectory = parentDir.path;
    } else {
      throw Exception(
        "Parent directory not found ${parentDir.path}",
      );
    }
  }
}