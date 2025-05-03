# Dart FTP Server

A simple, extensible FTP server implementation in Dart. Supports both read-only and read-and-write modes, with pluggable file system backends for flexible directory exposure and security.

---

## Table of Contents

- [Features](#features)
- [Compatibility](#compatibility)
- [Usage](#usage)
  - [Starting the Server](#starting-the-server)
  - [Running in the Background](#running-in-the-background)
  - [Supported Operations](#supported-operations)
  - [Authentication](#authentication)
  - [Read-Only Mode](#read-only-mode)
- [FTP Server File Operations](#ftp-server-file-operations)
  - [VirtualFileOperations](#1-virtualfileoperations)
  - [PhysicalFileOperations](#2-physicalfileoperations)
  - [Choosing an Implementation](#choosing-an-implementation)
  - [Limitations & Comparison](#limitations--comparison)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Passive and Active Modes**: Supports both passive and active data connections.
- **File Operations**: Retrieve, store, delete, and list files.
- **Directory Operations**: Change, make, and remove directories.
- **Read-Only Mode**: Disable write operations for enhanced security.
- **Authentication**: Basic username and password authentication.

## Compatibility

Tested on macOS. CI/CD test cases ensure compatibility with Linux and Windows.

## Usage

### Starting the Server

Here's an example of how to start the FTP server with a custom file operations backend (required):

```dart
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';

void main() async {
  final fileOps = VirtualFileOperations([
    '/home/user/ftp',
    '/home/user/other',
  ]);

  final server = FtpServer(
    21, // port
    username: 'user',
    password: 'pass',
    fileOperations: fileOps,
    serverType: ServerType.readAndWrite, // or ServerType.readOnly
  );

  await server.start();
}
```

> **BREAKING CHANGE:**
>
> - The `sharedDirectories` have been **removed** from `FtpServer`.
> - You must now create and pass a `FileOperations` instance (such as `VirtualFileOperations` or `PhysicalFileOperations`) directly to the `fileOperations` parameter.
> - All directory logic (e.g., shared directories and starting directory) is now handled by the provided `FileOperations` instance.
> - See the migration guide below for details.

#### Using PhysicalFileOperations

If you want to use a single physical directory as the FTP root (with no virtual mapping):

```dart
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';

void main() async {
  final fileOps = PhysicalFileOperations('/home/user/ftp_root');

  final server = FtpServer(
    21, // port
    username: 'user',
    password: 'pass',
    fileOperations: fileOps,
    serverType: ServerType.readAndWrite, // or ServerType.readOnly
  );

  await server.start();
}
```

For more information and advanced usage, see the [File Operations section](#ftp-server-file-operations) below.

### Running in the Background

You can run the FTP server in the background using the provided method:

```dart
await server.startInBackground();
```

This allows your Dart application to continue running other code while the FTP server handles connections in the background.

### Supported Operations

The server supports the following FTP commands:

| Command              | Description                                                 |
| -------------------- | ----------------------------------------------------------- |
| `USER <username>`    | Set the username for authentication.                        |
| `PASS <password>`    | Set the password for authentication.                        |
| `QUIT`               | Close the control connection.                               |
| `PASV`               | Enter passive mode.                                         |
| `PORT <host-port>`   | Enter active mode.                                          |
| `LIST [<directory>]` | List files in the specified directory or current directory. |
| `RETR <filename>`    | Retrieve the specified file.                                |
| `STOR <filename>`    | Store a file.                                               |
| `CWD <directory>`    | Change the current directory.                               |
| `CDUP`               | Change to the parent directory.                             |
| `MKD <directory>`    | Make a new directory.                                       |
| `RMD <directory>`    | Remove a directory.                                         |
| `DELE <filename>`    | Delete a file.                                              |
| `PWD`                | Print the current directory.                                |
| `SYST`               | Return system type.                                         |
| `NOOP`               | No operation (used to keep the connection alive).           |
| `SIZE <filename>`    | Return the size of the specified file.                      |

### Authentication

To enable authentication, provide the `username` and `password` parameters when creating the `FtpServer` instance. The server will then require clients to log in using these credentials.

### Read-Only Mode

To run the server in read-only mode, set the `serverType` parameter to `ServerType.readOnly`. In this mode, commands that modify the filesystem (e.g., `STOR`, `DELE`, `MKD`, `RMD`) will be disabled.

---

# FTP Server File Operations

This project provides two file operations backends for FTP and file management:

## 1. VirtualFileOperations

- Maps one or more physical directories to virtual root directories.
- Allows users to interact with a virtual file system, where each mapped directory appears as a top-level folder.
- Prevents access outside the mapped directories.
- **Limitation:** You cannot write to the virtual root directory (`/`). All file and directory operations must be within a mapped directory.

**Example:**

```dart
import 'package:ftp_server/file_operations/virtual_file_operations.dart';

final fileOps = VirtualFileOperations([
  '/path/to/dir/first',
  '/path/to/dir/second',
]);

// Change to a mapped directory
fileOps.changeDirectory('/first');
// Write a file
await fileOps.writeFile('example.txt', [1, 2, 3]);
// List files
final files = await fileOps.listDirectory('.');
// Read a file
final data = await fileOps.readFile('example.txt');
// Delete a file
await fileOps.deleteFile('example.txt');
```

## 2. PhysicalFileOperations

- Provides direct access to a single physical root directory.
- All operations are performed relative to this root.
- No virtual mapping or aliasing; paths are resolved directly.
- **Main difference:** You **can** write, create, and delete files/directories at the root directory in PhysicalFileOperations. This is not allowed in VirtualFileOperations.
- **Note:** In PhysicalFileOperations, `/` always refers to the root directory you provided.

**Example:**

```dart
import 'package:ftp_server/file_operations/physical_file_operations.dart';

final fileOps = PhysicalFileOperations('/path/to/root');

// Change to root ("/" always means the root you provided)
fileOps.changeDirectory('/');
// Write a file at the root
await fileOps.writeFile('root_file.txt', [4, 5, 6]);
// List files at the root
final files = await fileOps.listDirectory('/');
// Create a subdirectory
await fileOps.createDirectory('subdir');
// Write a file in a subdirectory
await fileOps.writeFile('subdir/hello.txt', [7, 8, 9]);
// Read a file
final data = await fileOps.readFile('subdir/hello.txt');
// Delete a file
await fileOps.deleteFile('subdir/hello.txt');
// Delete a directory
await fileOps.deleteDirectory('subdir');
```

## Choosing an Implementation

- Use **VirtualFileOperations** if you want to expose multiple directories as top-level folders or need to restrict access to specific directories.
- Use **PhysicalFileOperations** for direct, simple access to a single directory tree, with no virtual mapping, and if you need to allow operations at the root directory.

## Limitations & Comparison

| Feature / Limitation                 | VirtualFileOperations                   | PhysicalFileOperations                         |
| ------------------------------------ | --------------------------------------- | ---------------------------------------------- |
| **Allowed Roots**                    | Only mapped directories (virtual roots) | Only the provided root directory               |
| **Operation Outside Root**           | Not allowed (throws error)              | Not allowed (throws error)                     |
| **Writing to Root Directory**        | Not allowed (throws error for `/`)      | Allowed (can write files in `/`)               |
| **Creating/Deleting Root Directory** | Not allowed (throws error for `/`)      | Allowed (no-op for create, allowed for delete) |
| **Path `/` Meaning**                 | Virtual root (not system root)          | Provided root directory (not system root)      |
| **Security Checks**                  | Enforced for all mapped directories     | Enforced for the provided root                 |
| **Current Directory**                | Virtual, session-specific               | Physical, session-specific                     |

**Key Points:**

- Both implementations **enforce boundaries**: you cannot access or modify files outside the allowed root(s).
- **VirtualFileOperations** is stricter: it prevents any file or directory creation, deletion, or writing directly at the virtual root (`/`).
- **PhysicalFileOperations** is more permissive at its root: you can create, write, and delete files or directories at `/` (which is the root you provided, not the system root).

---

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your changes. Make sure to follow the existing code style and include tests for new features.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
