import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_operations.dart';

class VirtualFileOperations extends FileOperations {
  final Map<String, String> directoryMappings = {};

  VirtualFileOperations(List<String> allowedDirectories) : super('/') {
    if (allowedDirectories.isEmpty) {
      throw ArgumentError("Allowed directories cannot be empty");
    }

    for (String dir in allowedDirectories) {
      final normalizedDir = p.normalize(dir);
      final dirName = p.basename(normalizedDir);
      directoryMappings[dirName] = normalizedDir;
    }
  }

  @override
  String resolvePath(String path) {
    // If the path is empty or a relative path, append it to the current directory
    final effectivePath =
        p.isAbsolute(path) ? path : p.join(currentDirectory, path);

    final virtualPath = p.normalize(effectivePath);

    if (virtualPath == rootDirectory) {
      return rootDirectory;
    }

    final firstSegment = p.split(virtualPath).firstWhere(
        (part) => part.isNotEmpty && part != rootDirectory,
        orElse: () => rootDirectory);

    if (!directoryMappings.containsKey(firstSegment)) {
      throw FileSystemException("Access denied or directory not found: $path");
    }

    final mappedDir = directoryMappings[firstSegment]!;
    final remainingPath = p.relative(virtualPath, from: '/$firstSegment');

    final resolvedPath = p.normalize(p.join(mappedDir, remainingPath));
    return _resolvePathWithinRoot(resolvedPath);
  }

  @override
  void changeDirectory(String path) {
    final fullPath = resolvePath(path);

    if (Directory(fullPath).existsSync()) {
      final virtualDirName = directoryMappings.keys.firstWhere(
          (key) => fullPath.startsWith(directoryMappings[key]!),
          orElse: () => rootDirectory);

      currentDirectory = p.normalize(p.join(
          '/',
          virtualDirName,
          p.relative(fullPath,
              from: directoryMappings[virtualDirName] ?? "/")));
    } else {
      throw FileSystemException("Directory not found or access denied", path);
    }
  }

  @override
  void changeToParentDirectory() {
    if (currentDirectory == rootDirectory) {
      throw FileSystemException("Cannot navigate above root", currentDirectory);
    }

    final parentDir = p.dirname(currentDirectory);
    if (parentDir == rootDirectory) {
      currentDirectory = rootDirectory;
    } else {
      changeDirectory(parentDir);
    }
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    final fullPath = resolvePath(path);

    if (fullPath == rootDirectory) {
      return directoryMappings.values.map((dir) => Directory(dir)).toList();
    }

    final dir = Directory(fullPath);
    if (!await dir.exists()) {
      throw FileSystemException("Directory not found: $fullPath");
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
      throw FileSystemException("File not found: $path");
    }
    return file.readAsBytes();
  }

  @override
  Future<void> createDirectory(String path) async {
    final fullPath = resolvePath(path);
    final dir = Directory(fullPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    } else {
      throw FileSystemException("Directory Already found: $fullPath");
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = await getFile(path);
    if (await file.exists()) {
      await file.delete();
    } else {
      throw FileSystemException("File not found: $path");
    }
  }

  @override
  Future<void> deleteDirectory(String path) async {
    final dir = Directory(resolvePath(path));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    } else {
      throw FileSystemException("Directory not found: $path");
    }
  }

  @override
  Future<int> fileSize(String path) async {
    final file = await getFile(path);
    if (!await file.exists()) {
      throw FileSystemException("File not found: $path");
    }
    return await file.length();
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

  String _resolvePathWithinRoot(String path) {
    final normalizedPath = p.normalize(path);
    if (directoryMappings.values.any((dir) =>
        p.isWithin(dir, normalizedPath) || p.equals(dir, normalizedPath))) {
      return normalizedPath;
    } else {
      throw FileSystemException(
          "Access denied: Path is outside the allowed directories", path);
    }
  }
}
