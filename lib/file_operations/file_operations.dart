import 'dart:async';
import 'dart:io';

/// Interface defining common file operations for both physical and virtual file systems.
abstract class FileOperations {
  String rootDirectory;
  late String currentDirectory;

  FileOperations(this.rootDirectory) {
    currentDirectory = rootDirectory;
  }

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

  /// Resolves the given [path] relative to the [currentDirectory] and the specific file system rules (physical or virtual).
  ///
  /// Implementations must handle normalization, security checks (staying within allowed boundaries),
  /// and mapping (for virtual systems).
  String resolvePath(String path);

  /// Returns the current working directory.
  String getCurrentDirectory() {
    return currentDirectory;
  }

  /// Changes the current working directory to the specified path.
  /// Implementations must handle path resolution and update the internal state correctly.
  void changeDirectory(String path);

  /// Changes the current working directory to the parent directory.
  /// Implementations must handle path resolution and update the internal state correctly,
  /// including checks for navigating above the root.
  void changeToParentDirectory();

  /// Renames a file or directory from the old path to the new path.
  /// Both paths are relative to the current working directory.
  /// Implementations must handle path resolution and ensure the operation stays within allowed boundaries.
  Future<void> renameFileOrDirectory(String oldPath, String newPath);

  FileOperations copy();
}
