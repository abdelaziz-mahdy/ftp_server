import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_operations.dart';

/// Provides direct access to the physical file system, with no virtual mapping.
/// All operations are performed relative to a single root directory.
///
/// Main difference from VirtualFileOperations:
/// - PhysicalFileOperations allows writing, creating, and deleting files/directories at the root directory.
/// - VirtualFileOperations does NOT allow writing to the virtual root (`/`).
///
/// Limitations:
/// - Operations outside the root directory are not allowed.
/// - No virtual mapping or aliasing; paths are resolved directly.
class PhysicalFileOperations extends FileOperations {
  PhysicalFileOperations(String root, {String? startingDirectory})
      : super(p.normalize(root)) {
    if (!Directory(root).existsSync()) {
      throw ArgumentError("Root directory does not exist: $root");
    }
    currentDirectory = p.normalize(startingDirectory ?? rootDirectory);
    if (!p.isWithin(rootDirectory, currentDirectory) &&
        !p.equals(rootDirectory, currentDirectory)) {
      throw ArgumentError(
          "Starting directory must be within the root directory: $startingDirectory");
    }
  }

  @override
  String resolvePath(String path) {
    // '.' or '' means current directory, '/' means root
    if (path.isEmpty || path == '.') {
      return currentDirectory;
    }
    if (path == '/' || p.normalize(path) == p.separator) {
      return rootDirectory;
    }
    final cleanPath = p.normalize(path);
    final absPath = p.isAbsolute(cleanPath)
        ? p.normalize(p.join(rootDirectory, cleanPath.substring(1)))
        : p.normalize(p.join(currentDirectory, cleanPath));
    // Restrict to root
    if (!p.isWithin(rootDirectory, absPath) &&
        !p.equals(rootDirectory, absPath)) {
      throw FileSystemException(
          "Path resolution failed: Path is outside the root directory",
          absPath);
    }
    return absPath;
  }

  @override
  void changeDirectory(String path) {
    final targetPath = resolvePath(path);
    final dir = Directory(targetPath);
    if (!dir.existsSync() ||
        FileSystemEntity.typeSync(targetPath) !=
            FileSystemEntityType.directory) {
      throw FileSystemException(
          "Directory not found or not a directory: $path (resolved to $targetPath)",
          path);
    }
    currentDirectory = targetPath;
  }

  @override
  void changeToParentDirectory() {
    if (currentDirectory == rootDirectory) {
      throw FileSystemException("Cannot navigate above root", currentDirectory);
    }
    final parent = p.dirname(currentDirectory);
    changeDirectory(parent);
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    final dirPath = resolvePath(path);
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw FileSystemException(
          "Directory not found: $path (resolved to $dirPath)", path);
    }
    return dir.listSync();
  }

  @override
  Future<File> getFile(String path) async {
    final filePath = resolvePath(path);
    if (filePath == rootDirectory) {
      throw FileSystemException("Cannot get root as a file", path);
    }
    return File(filePath);
  }

  @override
  Future<void> writeFile(String path, List<int> data) async {
    final filePath = resolvePath(path);
    final file = File(filePath);
    // If the path exists and is a directory, throw
    if (await FileSystemEntity.type(filePath) ==
        FileSystemEntityType.directory) {
      throw FileSystemException(
          "Cannot write to a directory as a file", filePath);
    }
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  @override
  Future<List<int>> readFile(String path) async {
    final file = await getFile(path);
    if (!await file.exists()) {
      throw FileSystemException(
          "File not found: $path (resolved to ${file.path})");
    }
    return file.readAsBytes();
  }

  @override
  Future<void> createDirectory(String path) async {
    final dirPath = resolvePath(path);
    final dir = Directory(dirPath);
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
      throw FileSystemException(
          "File not found for deletion: $path (resolved to ${file.path})");
    }
  }

  @override
  Future<void> deleteDirectory(String path) async {
    final dirPath = resolvePath(path);
    final dir = Directory(dirPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    } else {
      throw FileSystemException(
          "Directory not found for deletion: $path (resolved to $dirPath)");
    }
  }

  @override
  Future<int> fileSize(String path) async {
    final file = await getFile(path);
    if (!await file.exists()) {
      throw FileSystemException(
          "File not found for size check: $path (resolved to ${file.path})");
    }
    return await file.length();
  }

  @override
  bool exists(String path) {
    try {
      final fullPath = resolvePath(path);
      if (fullPath == rootDirectory) return true;
      return File(fullPath).existsSync() || Directory(fullPath).existsSync();
    } catch (e) {
      return false;
    }
  }
}
