import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_operations.dart';

class VirtualFileOperations extends FileOperations {
  final Map<String, String> directoryMappings = {};

  /// Constructs a VirtualFileOperations object for managing directories.
  ///
  /// The `sharedDirectories` specifies directories that are accessible in this virtual file system.
  /// Throws [ArgumentError] if no directories are provided.
  VirtualFileOperations(List<String> allowedDirectories) : super(p.separator) {
    if (allowedDirectories.isEmpty) {
      throw ArgumentError("Allowed directories cannot be empty");
    }

    for (String dir in allowedDirectories) {
      // final normalizedDir = p.normalize(dir).replaceAll(r'\', '/');
      final normalizedDir = p.normalize(dir);
      final dirName = p.basename(normalizedDir);
      directoryMappings[dirName] = normalizedDir;
    }
  }
  @override
  String resolvePath(String path) {
    // Normalize path separators to use platform-specific separators
    path = path.replaceAll('\\', p.separator).replaceAll('/', p.separator);

    // If the path is empty or a relative path, append it to the current directory
    final effectivePath =
        p.isAbsolute(path) ? path : p.join(currentDirectory, path);

    // Normalize the path to handle ../, ./, etc.
    var virtualPath = p.normalize(effectivePath);

    // Handle the case where the root directory is requested
    if (virtualPath == rootDirectory) {
      return rootDirectory;
    }

    // Extract the first segment of the path to match against directory mappings
    final pathParts = p.split(virtualPath).where((part) => 
        part.isNotEmpty && part != p.rootPrefix(rootDirectory)).toList();
    
    if (pathParts.isEmpty) {
      return rootDirectory;
    }
    
    final firstSegment = pathParts.first;

    // Direct mapping check: first segment is a known mapped directory
    if (directoryMappings.containsKey(firstSegment)) {
      // Get the mapped directory and construct the remaining path
      final mappedDir = directoryMappings[firstSegment]!;
      final remainingPath =
          p.relative(virtualPath, from: '$rootDirectory$firstSegment');

      // Resolve the final path
      final resolvedPath = p.normalize(p.join(mappedDir, remainingPath));
      return _resolvePathWithinRoot(resolvedPath);
    }
    
    // If we're at root and the path doesn't start with a mapped directory, it's invalid
    if (currentDirectory == rootDirectory) {
      throw FileSystemException(
          "Access denied or directory not found: path requested $path, firstSegment is $firstSegment, "
          "currentDirectory is $currentDirectory, directoryMappings $directoryMappings");
    }
    
    // Handle relative paths from current directory
    if (currentDirectory != rootDirectory) {
      // Extract the first segment of the current directory to identify which mapped dir we're in
      final currentDirParts = p.split(currentDirectory)
          .where((part) => part.isNotEmpty && part != p.rootPrefix(rootDirectory))
          .toList();
      
      if (currentDirParts.isNotEmpty) {
        final currentDirRoot = currentDirParts.first;
        if (directoryMappings.containsKey(currentDirRoot)) {
          final mappedDir = directoryMappings[currentDirRoot]!;
          // Get the relative part of the current directory from the virtual root
          final relativePart = p.relative(currentDirectory, from: '$rootDirectory$currentDirRoot');
          // Construct physical path
          final fullPhysicalPath = p.normalize(p.join(mappedDir, relativePart, path));
          
          // Verify this path is still within the allowed directory
          if (p.isWithin(mappedDir, fullPhysicalPath) || p.equals(mappedDir, fullPhysicalPath)) {
            return fullPhysicalPath;
          }
        }
      }
    }
    
    // At this point, the path is not directly accessible via the virtual file system
    throw FileSystemException(
        "Access denied or directory not found: path requested $path, firstSegment is $firstSegment, "
        "currentDirectory is $currentDirectory, directoryMappings $directoryMappings");
  }

  // Helper method to check if a path is within any allowed directory
  bool _isWithinAllowedDirectories(String path) {
    return directoryMappings.values
        .any((dir) => p.isWithin(dir, path) || p.equals(dir, path));
  }

  String _resolvePathWithinRoot(String path) {
    final normalizedPath = p.normalize(path);

    // Ensure that the resolved path is within the allowed directories
    if (_isWithinAllowedDirectories(normalizedPath)) {
      return normalizedPath;
    } else {
      throw FileSystemException(
          "Access denied: Path is outside the allowed directories", path);
    }
  }

  @override
  void changeDirectory(String path) {
    final fullPath = resolvePath(path);

    if (Directory(fullPath).existsSync()) {
      final virtualDirName = directoryMappings.keys.firstWhere(
          (key) => fullPath.startsWith(directoryMappings[key]!),
          orElse: () => rootDirectory);

      currentDirectory = p.normalize(p.join(
          rootDirectory,
          virtualDirName,
          p.relative(fullPath,
              from: directoryMappings[virtualDirName] ?? rootDirectory)));
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
      throw FileSystemException(
          "File not found: $path, resolvedPath: ${resolvePath(path)}");
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
      throw FileSystemException(
          "File not found: $path, resolvedPath: ${resolvePath(path)}");
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
      throw FileSystemException(
          "File not found: $path, resolvedPath: ${resolvePath(path)}");
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
}
