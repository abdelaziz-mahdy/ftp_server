import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_operations.dart';

class VirtualFileOperations extends FileOperations {
  final Map<String, String> directoryMappings = {};

  /// Constructs a VirtualFileOperations object for managing directories.
  ///
  /// The `sharedDirectories` specifies directories that are accessible in this virtual file system.
  /// Throws [ArgumentError] if no directories are provided.
  VirtualFileOperations(
    List<String> allowedDirectories, {
    String startingDirectory = '/',
  }) : super(p.separator) {
    // rootDirectory is '/'

    // --- Start of changes ---
    // Normalize startingDirectory to be an absolute virtual path
    final String initialCurrentDirectory;
    if (p.isAbsolute(startingDirectory)) {
      initialCurrentDirectory = p.normalize(startingDirectory);
    } else {
      // Assume relative path is relative to root
      initialCurrentDirectory =
          p.normalize(p.join(rootDirectory, startingDirectory));
    }
    // --- End of changes ---

    if (allowedDirectories.isEmpty) {
      throw ArgumentError("Allowed directories cannot be empty");
    }

    for (String dir in allowedDirectories) {
      final normalizedDir = p.normalize(dir);
      final dirName = p.basename(normalizedDir);
      if (dirName == '.' || dirName == '..') {
        throw ArgumentError("Mapped directory name cannot be '.' or '..'");
      }
      if (directoryMappings.containsKey(dirName)) {
        throw ArgumentError("Duplicate mapped directory name: $dirName");
      }
      directoryMappings[dirName] = normalizedDir;
    }

    // --- Start of changes ---
    // Set currentDirectory AFTER mappings are potentially available for validation (optional)
    // We could add validation here using resolvePath, but let's try the simple fix first.
    currentDirectory = initialCurrentDirectory;
    // Optional validation:
    // try {
    //   resolvePath(currentDirectory); // Check if it resolves without error
    // } catch (e) {
    //   throw ArgumentError("Invalid starting directory '$startingDirectory': $e");
    // }
    // --- End of changes ---
  }

  @override
  String resolvePath(String path) {
    // Handle empty path or '.' - resolves relative to currentDirectory
    if (path.isEmpty || path == '.') {
      // If current directory is virtual root, return it.
      if (currentDirectory == rootDirectory) {
        return rootDirectory;
      }
      // Otherwise, resolve the current virtual directory to its physical path.
      return _virtualToPhysical(currentDirectory);
    }

    // Normalize input path separators and clean the path
    // Replace all backslashes with forward slashes for consistency
    // final normalizedPath = path.replaceAll('\\', '/');
    final cleanPath = p.normalize(path);

    // Determine the absolute virtual path
    final absoluteVirtualPath = p.isAbsolute(cleanPath)
        ? cleanPath
        : p.normalize(p.join(currentDirectory, cleanPath));

    // Handle the case where the resolved path is the virtual root directory
    if (absoluteVirtualPath == rootDirectory) {
      return rootDirectory;
    }

    // Optimization: If we are at the virtual root and the input path is relative,
    // try to directly resolve it against the physical base directories first
    if (currentDirectory == rootDirectory && !p.isAbsolute(cleanPath)) {
      final physicalPath = _tryDirectPhysicalResolution(cleanPath);
      if (physicalPath != null) {
        return physicalPath;
      }
    }

    // Standard resolution: Convert the absolute virtual path to its corresponding physical path
    return _virtualToPhysical(absoluteVirtualPath);
  }

  /// Converts an absolute virtual path to its corresponding physical path.
  /// Throws FileSystemException if the path is invalid or violates security constraints.
  String _virtualToPhysical(String virtualPath) {
    // The virtual root doesn't map to a single physical path, return it directly.
    if (virtualPath == rootDirectory) return rootDirectory;

    // Normalize the virtual path to use forward slashes
    final normalizedVirtualPath = p.normalize(virtualPath);

    // Split the virtual path into components, removing empty parts and the root '/'.
    final parts = p
        .split(normalizedVirtualPath)
        .where((part) => part.isNotEmpty && part != rootDirectory)
        .toList();

    // If there are no parts after splitting (e.g., path was just '/'), return root.
    if (parts.isEmpty) return rootDirectory;

    // The first part of the virtual path must be a key in our directory mappings.
    final mapKey = parts.first;
    if (!directoryMappings.containsKey(mapKey)) {
      throw FileSystemException(
          "Path resolution failed: Virtual directory '$mapKey' not found in '$virtualPath'. Available: ${directoryMappings.keys.join(', ')}",
          virtualPath);
    }

    // Get the physical base path corresponding to the virtual directory key.
    final physicalBase = directoryMappings[mapKey]!;
    // Get the remaining parts of the virtual path.
    final remainingParts = parts.length > 1 ? parts.sublist(1) : <String>[];
    // Construct the full physical path by joining the base and remaining parts.
    final physicalPath =
        p.normalize(p.joinAll([physicalBase, ...remainingParts]));

    // Security check: Ensure the resolved physical path is *within* or *equal to*
    // its corresponding physical base directory.
    if (!p.isWithin(physicalBase, physicalPath) &&
        !p.equals(physicalBase, physicalPath)) {
      throw FileSystemException(
          "Security constraint violated: Resolved path '$physicalPath' is outside its mapped directory '$physicalBase'",
          virtualPath);
    }

    return physicalPath;
  }

  /// Attempts to resolve a relative path directly against the physical mapped directories.
  /// This is used as an optimization when the current directory is the virtual root.
  /// Returns the physical path if found and valid, otherwise null.
  String? _tryDirectPhysicalResolution(String relativePath) {
    // Normalize the relative path to use forward slashes
    final normalizedRelativePath = relativePath.replaceAll('\\', '/');

    // Iterate through each mapping (e.g., 'docs' -> '/path/to/docs').
    for (final entry in directoryMappings.entries) {
      final physicalBase = entry.value;
      // Construct a potential physical path by joining the base and the relative path.
      final potentialPath =
          p.normalize(p.join(physicalBase, normalizedRelativePath));

      // Check if the potential path is valid:
      // 1. It must be within or equal to the physical base (security).
      // 2. The path must exist OR its parent directory must exist (allows creating new files/dirs).
      if ((p.isWithin(physicalBase, potentialPath) ||
              p.equals(physicalBase, potentialPath)) &&
          (FileSystemEntity.typeSync(potentialPath) !=
                  FileSystemEntityType.notFound ||
              // Check parent existence for potential new file/dir creation
              Directory(p.dirname(potentialPath)).existsSync())) {
        // If valid, return the resolved physical path.
        return potentialPath;
      }
    }
    // No direct resolution found.
    return null;
  }

  // Helper to get the virtual path from a physical path
  String _getVirtualPath(String physicalPath) {
    // Root directory maps to itself.
    if (physicalPath == rootDirectory) return rootDirectory;

    // Find which mapping the physical path belongs to.
    // It must be within or equal to one of the mapped physical directories.
    final entry = directoryMappings.entries.firstWhere(
      (e) =>
          p.isWithin(e.value, physicalPath) || p.equals(e.value, physicalPath),
      // If no mapping contains this physical path, it's an internal error,
      // likely meaning the physical path wasn't generated correctly by resolvePath.
      orElse: () => throw StateError(
          "Internal error: Cannot map physical path '$physicalPath' back to a virtual directory."),
    );

    // Calculate the path relative to the physical base directory.
    final relativePath = p.relative(physicalPath, from: entry.value);
    // Construct the full virtual path: / + mapping_key + relative_path
    return p.normalize(p.join(rootDirectory, entry.key, relativePath));
  }

  @override
  void changeDirectory(String path) {
    try {
      // First, resolve the target path (virtual or potentially physical relative)
      // to its absolute physical representation or the virtual root.
      final targetPhysicalPath = resolvePath(path);

      // Case 1: Resolved path is the virtual root.
      if (targetPhysicalPath == rootDirectory) {
        currentDirectory = rootDirectory;
        return;
      }

      // Case 2: Resolved path is a physical path. Check if it's a valid directory.
      final dir = Directory(targetPhysicalPath);
      if (!dir.existsSync()) {
        throw FileSystemException(
            "Directory not found: '$path' (resolved to '$targetPhysicalPath')",
            path);
      }
      // Ensure it's actually a directory (though existsSync often suffices).
      // Consider adding: if (FileSystemEntity.typeSync(targetPhysicalPath) != FileSystemEntityType.directory) { ... }

      // Update currentDirectory to the corresponding *virtual* path.
      // This ensures that subsequent relative operations work correctly within the virtual structure.
      currentDirectory = _getVirtualPath(targetPhysicalPath);
    } catch (e) {
      // Rethrow specific exceptions or wrap others for clarity.
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

      // Special Case: Listing the virtual root ('/').
      // We don't list a physical directory. Instead, we list the *keys*
      // of the directory mappings, representing the top-level virtual folders.
      if (resolvedPhysicalPath == rootDirectory) {
        // Return Directory objects where the path is just the mapping key (e.g., 'docs', 'pics').
        // This represents the virtual entries available at the root.
        // The FTP client will see these as directories.
        return directoryMappings.keys
            .map((key) =>
                Directory(key)) // Represent virtual entry using its key.
            .toList();
      }

      // Standard Case: Listing a directory within a mapping.
      // The resolved path is a physical directory path.
      final dir = Directory(resolvedPhysicalPath);
      if (!await dir.exists()) {
        throw FileSystemException(
            "Directory not found: '$path' (resolved to '$resolvedPhysicalPath')",
            path);
      }

      // Get the physical entities within the directory.
      // NOTE: listSync() can block on large directories. Consider async list() if performance is critical.
      final physicalEntities = dir.listSync();
      final virtualEntities = <FileSystemEntity>[];

      // Convert physical entities back to virtual representations.
      for (var entity in physicalEntities) {
        // Get the virtual path corresponding to the physical entity's path.
        final virtualPath = _getVirtualPath(entity.path);
        // Create a new FileSystemEntity (File or Directory) using the *virtual* path.
        // This is what the FTP client will see.
        if (entity is Directory) {
          virtualEntities.add(Directory(virtualPath));
        } else if (entity is File) {
          virtualEntities.add(File(virtualPath));
        }
        // Ignore other types like Links for simplicity, or handle as needed.
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

  // Helper: Checks if a path is a direct child of the virtual root (e.g., '/foo')
  bool _isDirectChildOfRoot(String path) {
    final virtualPath =
        p.normalize(p.isAbsolute(path) ? path : p.join(currentDirectory, path));

    final cleanPath = p.normalize(virtualPath);
    final parts = p.split(cleanPath).where((part) => part.isNotEmpty).toList();
    return parts.length == 1;
  }

  @override
  Future<void> writeFile(String path, List<int> data) async {
    if (_isDirectChildOfRoot(path)) {
      throw FileSystemException(
          "Cannot create or write file directly in the virtual root", path);
    }
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
    if (_isDirectChildOfRoot(path)) {
      throw FileSystemException(
          "Cannot create directory directly in the virtual root", path);
    }
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
    if (_isDirectChildOfRoot(path)) {
      throw FileSystemException(
          "Cannot delete file directly in the virtual root", path);
    }
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
    if (_isDirectChildOfRoot(path)) {
      throw FileSystemException(
          "Cannot delete directory directly in the virtual root", path);
    }
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
      print("Checking existence of: $fullPath");
      if (fullPath == rootDirectory) return true; // Virtual root always exists
      // Check both file and directory existence for the resolved physical path
      return File(fullPath).existsSync() || Directory(fullPath).existsSync();
    } catch (e) {
      // If resolvePath throws (e.g., invalid virtual path), it doesn't exist
      return false;
    }
  }
}
