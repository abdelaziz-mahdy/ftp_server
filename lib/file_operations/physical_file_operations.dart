import 'dart:io';
import 'file_operations.dart';

/// Implementation of [FileOperations] for interacting with the physical file system.
class PhysicalFileOperations extends FileOperations {
  /// Creates an instance of [PhysicalFileOperations] with the given root directory.
  PhysicalFileOperations(super.rootDirectory);

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
}
