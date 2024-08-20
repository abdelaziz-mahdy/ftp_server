import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_operations.dart';

/// Implementation of [FileOperations] for managing a virtual file system that maps to physical directories.
class VirtualFileOperations implements FileOperations {
  final List<String> allowedDirectories;
  String currentDirectory;

  /// Creates an instance of [VirtualFileOperations] with the given allowed directories.
  /// The initial current directory is set to the virtual root, represented by `/`.
  VirtualFileOperations(this.allowedDirectories) : currentDirectory = '/' {
    if (allowedDirectories.isEmpty) {
      throw ArgumentError("Allowed directories cannot be empty");
    }
  }

  /// Maps a virtual path to the corresponding physical path.
  /// Ensures that the path stays within the allowed directories.
  String _mapVirtualToPhysicalPath(String virtualPath) {
    String normalizedVirtualPath = p.normalize(virtualPath);

    if (normalizedVirtualPath == '/') {
      return '/';
    }

    for (var dir in allowedDirectories) {
      final normalizedDir = p.normalize(dir);
      String potentialPhysicalPath;

      if (virtualPath.startsWith('/')) {
        potentialPhysicalPath =
            p.join(normalizedDir, p.relative(normalizedVirtualPath, from: '/'));
      } else {
        potentialPhysicalPath = p.join(
            normalizedDir,
            p.relative(p.join(currentDirectory, normalizedVirtualPath),
                from: '/'));
      }

      potentialPhysicalPath = p.normalize(p.join(normalizedDir,
          p.relative(potentialPhysicalPath, from: normalizedDir)));

      if (p.isWithin(normalizedDir, potentialPhysicalPath) ||
          p.equals(normalizedDir, potentialPhysicalPath)) {
        return potentialPhysicalPath;
      }
    }

    throw FileSystemException(
        "Access denied or directory not found: $virtualPath");
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    try {
      final fullPath = resolvePath(path);

      if (fullPath == '/') {
        // Listing the virtual root should list all allowed directories
        return allowedDirectories.map((dir) => Directory(dir)).toList();
      }

      final dir = Directory(fullPath);
      if (!await dir.exists()) {
        throw FileSystemException("Directory not found: $fullPath");
      }
      return dir.listSync();
    } catch (e) {
      throw FileSystemException("Failed to list directory: $path, Error: $e");
    }
  }

  @override
  Future<File> getFile(String path) async {
    try {
      final fullPath = resolvePath(path);
      return File(fullPath);
    } catch (e) {
      throw FileSystemException("Failed to get file: $path, Error: $e");
    }
  }

  @override
  Future<void> writeFile(String path, List<int> data) async {
    try {
      final fullPath = resolvePath(path);
      final file = File(fullPath);
      await file.writeAsBytes(data);
    } catch (e) {
      throw FileSystemException("Failed to write file: $path, Error: $e");
    }
  }

  @override
  Future<List<int>> readFile(String path) async {
    try {
      final file = await getFile(path);
      if (!await file.exists()) {
        throw FileSystemException("File not found: $path");
      }
      return file.readAsBytes();
    } catch (e) {
      throw FileSystemException("Failed to read file: $path, Error: $e");
    }
  }

  @override
  Future<void> createDirectory(String path) async {
    try {
      final fullPath = resolvePath(path);
      final dir = Directory(fullPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      throw FileSystemException("Failed to create directory: $path, Error: $e");
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      final file = await getFile(path);
      if (await file.exists()) {
        await file.delete();
      } else {
        throw FileSystemException("File not found: $path");
      }
    } catch (e) {
      throw FileSystemException("Failed to delete file: $path, Error: $e");
    }
  }

  @override
  Future<void> deleteDirectory(String path) async {
    try {
      final dir = Directory(resolvePath(path));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      } else {
        throw FileSystemException("Directory not found: $path");
      }
    } catch (e) {
      throw FileSystemException("Failed to delete directory: $path, Error: $e");
    }
  }

  @override
  Future<int> fileSize(String path) async {
    try {
      final file = await getFile(path);
      if (!await file.exists()) {
        throw FileSystemException("File not found: $path");
      }
      return await file.length();
    } catch (e) {
      throw FileSystemException("Failed to get file size: $path, Error: $e");
    }
  }

  @override
  bool exists(String path) {
    try {
      final fullPath = resolvePath(path);
      return File(fullPath).existsSync() || Directory(fullPath).existsSync();
    } catch (e) {
      return false;
    }
  }

  @override
  String resolvePath(String path) {
    if (currentDirectory == '/' && path == '/') {
      return '/';
    }
    return _mapVirtualToPhysicalPath(path);
  }

  @override
  String getCurrentDirectory() {
    return currentDirectory;
  }

  @override
  void changeDirectory(String path) {
    try {
      final fullPath = resolvePath(path);

      if (fullPath == '/') {
        currentDirectory = '/';
      } else if (Directory(fullPath).existsSync()) {
        currentDirectory = fullPath;
      } else {
        throw FileSystemException("Directory not found: $fullPath");
      }
    } catch (e) {
      throw FileSystemException("Failed to change directory: $path, Error: $e");
    }
  }

  @override
  void changeToParentDirectory() {
    if (currentDirectory == '/') {
      throw FileSystemException(
          "Cannot navigate above root: $currentDirectory");
    }

    final parentDir = Directory(currentDirectory).parent;
    currentDirectory = parentDir.path;
  }
}
