import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_operations.dart';

class VirtualFileOperations extends FileOperations {
  final Map<String, String> directoryMappings = {};

  /// Creates an instance of [VirtualFileOperations] with the given allowed directories.
  /// Maps directory names to their full paths internally.
  VirtualFileOperations(List<String> allowedDirectories) : super('/') {
    if (allowedDirectories.isEmpty) {
      throw ArgumentError("Allowed directories cannot be empty");
    }

    // Create a mapping from directory names to their full paths
    for (String dir in allowedDirectories) {
      final normalizedDir = p.normalize(dir);
      final dirName = p.basename(normalizedDir);
      directoryMappings[dirName] = normalizedDir;
    }
  }

  /// Maps a virtual path to the corresponding physical path.
  /// Ensures that the path stays within the mapped directories.
  @override
  String resolvePath(String path) {
    String normalizedPath = super.resolvePath(path);
    if (normalizedPath == rootDirectory) {
      return rootDirectory;
    }
    // Check if the path is absolute
    if (p.isAbsolute(path)) {
      normalizedPath = p.relative(normalizedPath, from: rootDirectory);
      // Extract the first part of the path (the directory name)
      String dirName = p
          .split(normalizedPath)
          .firstWhere((part) => part.isNotEmpty && part != rootDirectory);

      // Match the directory name against the mappings
      if (directoryMappings.containsKey(dirName)) {
        // Get the corresponding physical path
        String mappedDir = directoryMappings[dirName]!;

        // Construct the full path by replacing the virtual root with the mapped directory
        String remainingPath = normalizedPath.substring(dirName.length);
        if (remainingPath.startsWith(rootDirectory)) {
          remainingPath = remainingPath.substring(1);
        }
        return p.normalize(p.join(mappedDir, remainingPath));
      } else {
        throw FileSystemException(
            "Access denied or directory not found: $path");
      }
    } else {
      // For relative paths, resolve it against the current directory
      String currentDir = getCurrentDirectory();
      String potentialPhysicalPath = p.join(currentDir, normalizedPath);
      return potentialPhysicalPath;
    }
  }

  // Other methods remain the same, utilizing the new resolvePath method
  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    try {
      final fullPath = resolvePath(path);

      if (fullPath == rootDirectory) {
        // Listing the virtual root should list all mapped directories
        return directoryMappings.values.map((dir) => Directory(dir)).toList();
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
}
