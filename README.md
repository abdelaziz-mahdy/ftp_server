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

This project provides two ways to share files and folders over FTP:

- **Virtual (Multiple Directories):** Share several folders as top-level directories. Good for when you want to give access to multiple, separate folders.
- **Physical (Single Directory):** Share one folder as the FTP root. Good for when you want to give access to everything inside a single folder.

## 1. VirtualFileOperations (Multiple Directories)

- Lets you share several folders, and each appears as a separate top-level folder when users connect.
- Users cannot add, edit, or delete files directly at the root ("/"). They can only work inside the folders you shared.
- Example: If you share `/photos` and `/docs`, users will see two folders: `photos` and `docs` at the top level.
- **Use this if:** You want to share multiple folders and keep them separate.

## 2. PhysicalFileOperations (Single Directory)

- Lets you share one folder as the root of the FTP server.
- Users can add, edit, or delete files and folders directly inside this root folder.
- Example: If you share `/home/user/ftp_root`, users will see all files and folders inside `ftp_root` and can manage them freely.
- **Use this if:** You want to share everything inside a single folder and allow full access within it.

## Quick Comparison

| Feature                      | Virtual (Multiple Directories)   | Physical (Single Directory)        |
| ---------------------------- | -------------------------------- | ---------------------------------- |
| Number of shared folders     | Multiple                         | One                                |
| Can add/edit/delete at root? | No                               | Yes                                |
| Root meaning                 | Virtual root (not a real folder) | The folder you chose as the root   |
| Best for                     | Sharing several separate folders | Sharing one folder and its content |

## Choosing an Implementation

- Use **VirtualFileOperations** if you want to expose multiple directories as top-level folders or need to restrict access to specific directories.
- Use **PhysicalFileOperations** for direct, simple access to a single directory tree, with no virtual mapping, and if you need to allow operations at the root directory.

**Key Points:**

- Both implementations **enforce boundaries**: you cannot access or modify files outside the allowed root(s).
- **Neither implementation allows deleting the root directory** (`/`). Attempting to do so will throw an error.
- **VirtualFileOperations** is stricter: it prevents any file or directory creation, deletion, or writing directly at the virtual root (`/`).
- **PhysicalFileOperations** allows creating and writing files at its root, but not deleting it (the root is the directory you provided, not the system root).

---

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your changes. Make sure to follow the existing code style and include tests for new features.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
