import 'dart:async';
import 'dart:io';

/// Interface defining common file operations for both physical and virtual file systems.
abstract class FileOperations {
  
  /// Lists the contents of the directory at the given path.
  /// Returns a list of [FileSystemEntity] objects representing the contents.
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

  /// Resolves the given virtual or relative path to an absolute path in the underlying file system.
  String resolvePath(String path);

  /// Returns the current working directory.
  String getCurrentDirectory();

  /// Changes the current working directory to the specified path.
  void changeDirectory(String path);

  /// Changes the current working directory to the parent directory.
  void changeToParentDirectory();
}
