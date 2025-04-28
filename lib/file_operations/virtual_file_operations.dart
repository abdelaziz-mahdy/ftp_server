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
      final normalizedDir = p.normalize(dir);
      final dirName = p.basename(normalizedDir);
      directoryMappings[dirName] = normalizedDir;
    }
  }

  @override
  String resolvePath(String path) {
    // Handle empty path - return current directory's physical path
    if (path.isEmpty) {
      if (currentDirectory == rootDirectory) {
        return rootDirectory;
      }
      return _virtualToPhysical(currentDirectory);
    }

    // Normalize input path separators and clean the path
    final cleanPath = p.normalize(path.replaceAll('\\', p.separator));

    // Determine the absolute virtual path
    final absoluteVirtualPath = p.isAbsolute(cleanPath)
        ? cleanPath
        : p.normalize(p.join(currentDirectory, cleanPath));

    // Handle root directory case
    if (absoluteVirtualPath == rootDirectory) {
      return rootDirectory;
    }

    // Special case: If at root and path is relative, try direct physical resolution first
    if (currentDirectory == rootDirectory && !p.isAbsolute(cleanPath)) {
      final physicalPath = _tryDirectPhysicalResolution(cleanPath);
      if (physicalPath != null) {
        return physicalPath;
      }
    }

    // Standard virtual path resolution
    return _virtualToPhysical(absoluteVirtualPath);
  }

  String _virtualToPhysical(String virtualPath) {
    if (virtualPath == rootDirectory) return rootDirectory;

    final parts = p
        .split(virtualPath)
        .where((part) => part.isNotEmpty && part != rootDirectory)
        .toList();

    if (parts.isEmpty) return rootDirectory;

    final mapKey = parts.first;
    if (!directoryMappings.containsKey(mapKey)) {
      throw FileSystemException(
          "Path resolution failed: Virtual directory '$mapKey' not found in '$virtualPath'. Available: ${directoryMappings.keys.join(', ')}",
          virtualPath);
    }

    final physicalBase = directoryMappings[mapKey]!;
    final remainingParts = parts.length > 1 ? parts.sublist(1) : <String>[];
    final physicalPath =
        p.normalize(p.joinAll([physicalBase, ...remainingParts]));

    // Security check: Ensure resolved path is within its physical base
    if (!p.isWithin(physicalBase, physicalPath) &&
        !p.equals(physicalBase, physicalPath)) {
      throw FileSystemException(
          "Security constraint violated: Resolved path '$physicalPath' is outside its mapped directory '$physicalBase'",
          virtualPath);
    }

    return physicalPath;
  }

  String? _tryDirectPhysicalResolution(String relativePath) {
    for (final entry in directoryMappings.entries) {
      final physicalBase = entry.value;
      final potentialPath = p.normalize(p.join(physicalBase, relativePath));

      if ((p.isWithin(physicalBase, potentialPath) ||
              p.equals(physicalBase, potentialPath)) &&
          (FileSystemEntity.typeSync(potentialPath) !=
                  FileSystemEntityType.notFound ||
              Directory(p.dirname(potentialPath)).existsSync())) {
        return potentialPath;
      }
    }
    return null;
  }

  // Helper to get the virtual path from a physical path
  String _getVirtualPath(String physicalPath) {
    if (physicalPath == rootDirectory) return rootDirectory;

    // Find which mapping the physical path belongs to
    final entry = directoryMappings.entries.firstWhere(
      (e) =>
          p.isWithin(e.value, physicalPath) || p.equals(e.value, physicalPath),
      orElse: () => throw StateError(
          "Internal error: Cannot map physical path '$physicalPath' back to a virtual directory."),
    );

    // Calculate the relative path from the physical base
    final relativePath = p.relative(physicalPath, from: entry.value);
    // Construct the full virtual path
    return p.normalize(p.join(rootDirectory, entry.key, relativePath));
  }

  @override
  void changeDirectory(String path) {
    try {
      final targetPhysicalPath = resolvePath(path);

      // Special case for resolving to virtual root
      if (targetPhysicalPath == rootDirectory) {
        currentDirectory = rootDirectory;
        return;
      }

      // Check if the physical path exists and is a directory
      final dir = Directory(targetPhysicalPath);
      if (!dir.existsSync()) {
        throw FileSystemException(
            "Directory not found: '$path' (resolved to '$targetPhysicalPath')",
            path);
      }

      // If we're at root and path is relative, try to find which mapping it belongs to
      if (currentDirectory == rootDirectory && !p.isAbsolute(path)) {
        for (final entry in directoryMappings.entries) {
          if (p.isWithin(entry.value, targetPhysicalPath) ||
              p.equals(entry.value, targetPhysicalPath)) {
            // Found the mapping, update currentDirectory with virtual path
            final relativePath =
                p.relative(targetPhysicalPath, from: entry.value);
            currentDirectory =
                p.normalize(p.join('/', entry.key, relativePath));
            return;
          }
        }
      }

      // Update currentDirectory to the corresponding *virtual* path
      currentDirectory = _getVirtualPath(targetPhysicalPath);
    } catch (e) {
      // Rethrow specific exceptions or wrap others
      if (e is FileSystemException || e is StateError) {
        rethrow;
      }
      throw FileSystemException(
          "Failed to change directory to '$path': ${e.toString()}", path);
    }
  }

  @override
  void changeToParentDirectory() {
    if (currentDirectory == rootDirectory) {
      throw FileSystemException("Cannot navigate above root", currentDirectory);
    }
    // Calculate parent virtual directory using path package
    final parentVirtualDir = p.dirname(currentDirectory);
    // Use changeDirectory to handle the logic and state update
    changeDirectory(parentVirtualDir);
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    try {
      final resolvedPhysicalPath = resolvePath(path);

      // If resolved path is the virtual root, ONLY list the mapped virtual directories (keys).
      if (resolvedPhysicalPath == rootDirectory) {
        // Return Directory objects representing the *keys* of the mappings.
        return directoryMappings.keys
            .map((key) => Directory(key)) // Represent using only the key name
            .toList();
      }

      // Otherwise (resolved path is a physical path), list the contents of that directory
      final dir = Directory(resolvedPhysicalPath);
      if (!await dir.exists()) {
        throw FileSystemException(
            "Directory not found: '$path' (resolved to '$resolvedPhysicalPath')",
            path);
      }

      // Get the physical entities and map them to virtual paths
      final physicalEntities = dir.listSync();
      final virtualEntities = <FileSystemEntity>[];

      for (var entity in physicalEntities) {
        // Get the virtual path for this entity
        final virtualPath = _getVirtualPath(entity.path);
        // Create a new entity with the virtual path
        if (entity is Directory) {
          virtualEntities.add(Directory(virtualPath));
        } else if (entity is File) {
          virtualEntities.add(File(virtualPath));
        }
      }

      return virtualEntities;
    } catch (e) {
      if (e is FileSystemException) {
        rethrow;
      }
      throw FileSystemException(
          "Failed to list directory '$path': ${e.toString()}", path);
    }
  }

  @override
  Future<File> getFile(String path) async {
    // Resolve path first, handle root case if necessary (though getFile on root is unlikely)
    final fullPath = resolvePath(path);
    if (fullPath == rootDirectory) {
      throw FileSystemException("Cannot get root as a file", path);
    }
    return File(fullPath);
  }

  @override
  Future<void> writeFile(String path, List<int> data) async {
    final fullPath = resolvePath(path);
    if (fullPath == rootDirectory) {
      throw FileSystemException("Cannot write to root directory", path);
    }
    final file = File(fullPath);
    // Ensure parent directory exists before writing
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  @override
  Future<List<int>> readFile(String path) async {
    final file =
        await getFile(path); // getFile already resolves and handles root
    if (!await file.exists()) {
      throw FileSystemException(
          "File not found: $path (resolved to ${file.path})");
    }
    return file.readAsBytes();
  }

  @override
  Future<void> createDirectory(String path) async {
    try {
      final fullPath = resolvePath(path);
      if (fullPath == rootDirectory) {
        throw FileSystemException("Cannot create root directory", path);
      }
      final dir = Directory(fullPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      } else {
        // Optional: Decide if this should be an error or silently succeed
        // throw FileSystemException("Directory already exists: '$path' (resolved to '$fullPath')", path);
      }
    } catch (e) {
      if (e is FileSystemException) {
        rethrow;
      }
      throw FileSystemException(
          "Failed to create directory '$path': ${e.toString()}", path);
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    final file =
        await getFile(path); // getFile already resolves and handles root
    if (await file.exists()) {
      await file.delete();
    } else {
      throw FileSystemException(
          "File not found for deletion: $path (resolved to ${file.path})");
    }
  }

  @override
  Future<void> deleteDirectory(String path) async {
    final fullPath = resolvePath(path);
    if (fullPath == rootDirectory) {
      throw FileSystemException("Cannot delete root directory", path);
    }
    final dir = Directory(fullPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    } else {
      throw FileSystemException(
          "Directory not found for deletion: $path (resolved to $fullPath)");
    }
  }

  @override
  Future<int> fileSize(String path) async {
    final file =
        await getFile(path); // getFile already resolves and handles root
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
      if (fullPath == rootDirectory) return true; // Virtual root always exists
      // Check both file and directory existence for the resolved physical path
      return FileSystemEntity.typeSync(fullPath) !=
          FileSystemEntityType.notFound;
    } catch (e) {
      // If resolvePath throws (e.g., invalid virtual path), it doesn't exist
      return false;
    }
  }
}
