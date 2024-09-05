import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Interface defining common file operations for both physical and virtual file systems.
abstract class FileOperations {
  String rootDirectory;
  String currentDirectory;

  FileOperations(this.rootDirectory) : currentDirectory = rootDirectory;

  /// Lists the contents of the directory at the given path.
  Future<List<FileSystemEntity>> listDirectory(String path);

  /// Retrieves a [File] object for the given path.
  Future<File> getFile(String path);

  /// Writes data to a file at the specified path.
  Future<void> writeFile(String path, List<int> data);

  /// Reads and returns the data from the file at the specified path.
  Future<List<int>> readFile(String path);

  /// Creates a directory at the specified path.
  Future<void> createDirectory(String path);

  /// Deletes the file at the specified path.
  Future<void> deleteFile(String path);

  /// Deletes the directory at the specified path.
  Future<void> deleteDirectory(String path);

  /// Returns the size of the file at the specified path.
  Future<int> fileSize(String path);

  /// Checks if a file or directory exists at the specified path.
  bool exists(String path);

  /// Resolves the given [path] relative to the [currentDirectory].
  /// The resolved path is normalized and checked to ensure it stays within the [rootDirectory].
  ///
  /// If the [path] is absolute and matches part of the [currentDirectory], the common prefix is removed.
  ///
  /// If the [path] is relative, it is resolved relative to the [currentDirectory].
  ///
  /// Examples:
  /// ```dart
  /// // Given rootDirectory = '/home/user/project' and currentDirectory = '/home/user/project/subdir'
  /// resolvePath('file.txt'); // Returns: '/home/user/project/subdir/file.txt'
  /// resolvePath('/home/user/project/subdir/file.txt'); // Returns: '/home/user/project/subdir/file.txt'
  /// resolvePath('/home/user'); // Throws FileSystemException (outside root)
  /// resolvePath('../../file.txt'); // Throws FileSystemException (attempt to go above root)
  /// ```
  String resolvePath(String path) {
    // Normalize both the current directory and the provided path
    String normalizedCurrentDir = p.normalize(currentDirectory);
    String normalizedRootDirectory = p.normalize(rootDirectory);
    String normalizedPath = p.normalize(path);

    // If the path is absolute, strip the common prefix with the current directory
    if (p.isAbsolute(normalizedPath)) {
      if (normalizedPath.startsWith(normalizedRootDirectory)) {
        // Remove the common prefix (root directory) from the path
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

  /// Helper method to ensure the path stays within the root directory.
  String _resolvePathWithinRoot(String path) {
    // Preliminary check for any attempt to traverse above the root directory
    final upLevelCount = path.split('/').where((part) => part == '..').length;
    final rootParts = p.split(p.normalize(rootDirectory)).length;

    // If the number of "../" sequences exceeds the depth of the root directory, it's invalid
    if (upLevelCount > rootParts) {
      throw FileSystemException(
          "Access denied: Path is attempting to escape the root directory",
          path);
    }

    // Normalize and join the path after the check
    final resolvedPath = p.normalize(p.join(rootDirectory, path));

    // Your original condition remains unchanged
    if (!p.isWithin(rootDirectory, resolvedPath) &&
        (rootDirectory != resolvedPath)) {
      throw FileSystemException(
          "Access denied: Path is outside the root directory", path);
    }

    return resolvedPath;
  }

  /// Returns the current working directory.
  String getCurrentDirectory() {
    return currentDirectory;
  }

  /// Changes the current working directory to the specified path.
  void changeDirectory(String path) {
    final fullPath = resolvePath(path);
    if (Directory(fullPath).existsSync()) {
      currentDirectory = fullPath;
    } else {
      throw FileSystemException("Directory not found", fullPath);
    }
  }

  /// Changes the current working directory to the parent directory.
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
