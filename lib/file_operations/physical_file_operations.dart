import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_operations.dart';

/// Implementation of [FileOperations] for interacting with the physical file system.
class PhysicalFileOperations implements FileOperations {
  final String rootDirectory;
  String currentDirectory;

  /// Creates an instance of [PhysicalFileOperations] with the given root directory.
  PhysicalFileOperations(this.rootDirectory) : currentDirectory = rootDirectory;

  /// Resolves a path to ensure it is within the root directory.
  String _resolvePathWithinRoot(String path) {
    // Resolve the path within the root directory
    final resolvedPath = p.normalize(p.join(rootDirectory, path));
    if (!p.isWithin(rootDirectory, resolvedPath) &&
        (rootDirectory != resolvedPath)) {
      throw FileSystemException(
          "Access denied: Path is outside the root directory", path);
    }
    return resolvedPath;
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    final fullPath = resolvePath(path);
    final dir = Directory(fullPath);
    if (!await dir.exists()) {
      throw FileSystemException("Directory not found", fullPath);
    }
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
    if (!await file.exists()) {
      throw FileSystemException("File not found", path);
    }
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
    } else {
      throw FileSystemException("File not found", path);
    }
  }

  @override
  Future<void> deleteDirectory(String path) async {
    final dir = Directory(resolvePath(path));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    } else {
      throw FileSystemException("Directory not found", path);
    }
  }

  @override
  Future<int> fileSize(String path) async {
    final file = await getFile(path);
    if (!await file.exists()) {
      throw FileSystemException("File not found", path);
    }
    return await file.length();
  }

  @override
  bool exists(String path) {
    final fullPath = resolvePath(path);
    return File(fullPath).existsSync() || Directory(fullPath).existsSync();
  }

  @override
  String resolvePath(String path) {
    // Normalize both the current directory and the provided path
    String normalizedCurrentDir = p.normalize(currentDirectory);
    String normalizedRootDirectory = p.normalize(rootDirectory);

    String normalizedPath = p.normalize(path);

    // If the path is absolute, strip the common prefix with the current directory
    if (p.isAbsolute(normalizedPath)) {
      if (normalizedPath.startsWith(normalizedRootDirectory)) {
        // Remove the common prefix (current directory) from the path
        normalizedPath =
            p.relative(normalizedPath, from: normalizedRootDirectory);
      }
      if (p.isAbsolute(normalizedPath)) {
        // Resolve the remaining path relative to the root directory
        return _resolvePathWithinRoot(p.relative(normalizedPath, from: '/'));
      } else {
        return _resolvePathWithinRoot(normalizedPath);
      }
    } else {
      // For relative paths, resolve it as usual
      return _resolvePathWithinRoot(
          p.join(normalizedCurrentDir, normalizedPath));
    }
  }

  @override
  String getCurrentDirectory() {
    return currentDirectory;
  }

  @override
  void changeDirectory(String path) {
    final fullPath = resolvePath(path);
    if (Directory(fullPath).existsSync()) {
      currentDirectory = fullPath;
    } else {
      throw FileSystemException("Directory not found", fullPath);
    }
  }

  @override
  void changeToParentDirectory() {
    if (currentDirectory == rootDirectory) {
      throw FileSystemException("Cannot navigate above root", currentDirectory);
    }

    final parentDir = Directory(currentDirectory).parent;
    if (p.isWithin(rootDirectory, parentDir.path) ||
        parentDir.path == rootDirectory) {
      currentDirectory = parentDir.path;
    } else {
      throw FileSystemException(
          "Access denied: Cannot navigate above root", currentDirectory);
    }
  }
}
