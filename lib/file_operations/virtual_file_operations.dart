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
    // Handle empty path case first
    if (path.isEmpty) {
      // If current directory is root, return root. Otherwise, resolve current dir.
      if (currentDirectory == rootDirectory) {
        return rootDirectory;
      }
      // Need to resolve the current virtual directory to its physical path
      // This requires splitting the current virtual path and finding the mapping
      final parts = p
          .split(currentDirectory)
          .where((part) => part.isNotEmpty && part != rootDirectory)
          .toList();
      if (parts.isEmpty) {
        return rootDirectory; // Should not happen if not root, but safe check
      }
      final mapKey = parts.first;
      if (!directoryMappings.containsKey(mapKey)) {
        throw StateError(
            "Internal error: Current directory '$currentDirectory' has invalid mapping key '$mapKey'");
      }
      final physicalBase = directoryMappings[mapKey]!;
      final remainingParts = parts.length > 1 ? parts.sublist(1) : <String>[];
      return p.normalize(p.joinAll([physicalBase, ...remainingParts]));
    }

    // 1. Normalize input path separators
    final cleanPath =
        path.replaceAll('\\', p.separator).replaceAll('/', p.separator);

    // 2. Determine the absolute virtual path (tentative)
    final String absoluteVirtualPath;
    final bool isInputAbsolute = p.isAbsolute(cleanPath);
    if (isInputAbsolute) {
      absoluteVirtualPath = p.normalize(cleanPath);
    } else {
      absoluteVirtualPath = p.normalize(p.join(currentDirectory, cleanPath));
    }

    // 3. Handle virtual root directory explicitly
    if (absoluteVirtualPath == rootDirectory) {
      return rootDirectory; // Represents the virtual root, not a physical path
    }

    // 4. Lenient check for relative paths from root
    if (currentDirectory == rootDirectory && !isInputAbsolute) {
      for (final entry in directoryMappings.entries) {
        final physicalBase = entry.value;
        final potentialPhysicalPath =
            p.normalize(p.join(physicalBase, cleanPath));

        // Security check: Must be within the base
        if (p.isWithin(physicalBase, potentialPhysicalPath) ||
            p.equals(physicalBase, potentialPhysicalPath)) {
          final parentExists =
              Directory(p.dirname(potentialPhysicalPath)).existsSync();
          final selfType = FileSystemEntity.typeSync(potentialPhysicalPath);

          if (selfType != FileSystemEntityType.notFound || parentExists) {
            return potentialPhysicalPath; // Found a valid match
          }
        }
      }
      // Fall through if no match found in lenient check
    }

    // 5. Standard virtual path resolution (split virtual path, find mapping)
    final parts = p
        .split(absoluteVirtualPath)
        .where((part) => part.isNotEmpty && part != rootDirectory)
        .toList();

    if (parts.isEmpty) {
      return rootDirectory; // Resolved to root after normalization
    }

    final mapKey = parts.first;
    if (!directoryMappings.containsKey(mapKey)) {
      // This error occurs if the path doesn't start with a known key
      throw FileSystemException(
          "Path resolution failed: Virtual directory '$mapKey' not found in '$absoluteVirtualPath'. Available: ${directoryMappings.keys.join(', ')}",
          absoluteVirtualPath);
    }

    // 6. Construct the physical path
    final physicalBase = directoryMappings[mapKey]!;
    final remainingParts = parts.length > 1 ? parts.sublist(1) : <String>[];
    final physicalPath =
        p.normalize(p.joinAll([physicalBase, ...remainingParts]));

    // 7. Security check: Ensure the resolved physical path is within its corresponding physical base
    if (!p.isWithin(physicalBase, physicalPath) &&
        !p.equals(physicalBase, physicalPath)) {
      throw FileSystemException(
          "Security constraint violated: Resolved path '$physicalPath' is outside its mapped directory '$physicalBase'",
          absoluteVirtualPath);
    }

    return physicalPath; // Ensure physicalPath is defined and returned from step 6/7
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
      // Return the actual physical entities found
      return dir.listSync(); // Using sync for simplicity
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
