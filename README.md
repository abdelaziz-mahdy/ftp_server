# Dart FTP Server

A simple, extensible FTP server implementation in Dart. Supports both read-only and read-and-write modes, with pluggable file system backends for flexible directory exposure and security.

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Features](#2-features)
3. [Compatibility](#3-compatibility)
4. [Usage](#4-usage)
   - [Starting the Server](#41-starting-the-server)
   - [Running in the Background](#42-running-in-the-background)
   - [Supported FTP Commands](#43-supported-ftp-commands)
   - [Authentication](#44-authentication)
   - [Read-Only Mode](#45-read-only-mode)
5. [File Sharing Backends](#5-file-sharing-backends)
   - [Quick Comparison](#51-quick-comparison)
   - [Virtual (Multiple Directories)](#52-virtual-multiple-directories)
   - [Physical (Single Directory)](#53-physical-single-directory)
   - [Choosing a Backend](#54-choosing-a-backend)
   - [Key Points](#55-key-points)
6. [Contributing](#6-contributing)
7. [License](#7-license)

---

## 1. Quick Start

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

- See [File Sharing Backends](#5-file-sharing-backends) for how to use a single directory (Physical backend).
- For more advanced usage, see the sections below.

---

## 2. Features

- **Passive and Active Modes**: Supports both passive and active data connections.
- **File Operations**: Retrieve, store, delete, and list files.
- **Directory Operations**: Change, make, and remove directories.
- **Read-Only Mode**: Disable write operations for enhanced security.
- **Authentication**: Basic username and password authentication.

---

## 3. Compatibility

Tested on macOS. CI/CD test cases ensure compatibility with Linux and Windows.

---

## 4. Usage

### 4.1 Starting the Server

See [Quick Start](#1-quick-start) above for a basic example.

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

### 4.2 Running in the Background

You can run the FTP server in the background using the provided method:

```dart
await server.startInBackground();
```

This allows your Dart application to continue running other code while the FTP server handles connections in the background.

### 4.3 Supported FTP Commands

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
| `RNFR <filename>`    | Rename from (specify source file/directory for rename).     |
| `RNTO <filename>`    | Rename to (specify destination file/directory for rename).  |
| `RENAME <old> <new>` | Rename a file or directory (high-level command).            |

### 4.4 Authentication

To enable authentication, provide the `username` and `password` parameters when creating the `FtpServer` instance. The server will then require clients to log in using these credentials.

### 4.5 Read-Only Mode

To run the server in read-only mode, set the `serverType` parameter to `ServerType.readOnly`. In this mode, commands that modify the filesystem (e.g., `STOR`, `DELE`, `MKD`, `RMD`) will be disabled.

---

## 5. File Sharing Backends

This project provides two ways to share files and folders over FTP:

### 5.1 Quick Comparison

| Feature                      | Virtual (Multiple Directories)   | Physical (Single Directory)        |
| ---------------------------- | -------------------------------- | ---------------------------------- |
| Number of shared folders     | Multiple                         | One                                |
| Can add/edit/delete at root? | No                               | Yes                                |
| Root meaning                 | Virtual root (not a real folder) | The folder you chose as the root   |
| Best for                     | Sharing several separate folders | Sharing one folder and its content |

### 5.2 Virtual (Multiple Directories)

- Lets you share several folders, and each appears as a separate top-level folder when users connect.
- Users cannot add, edit, or delete files directly at the root ("/"). They can only work inside the folders you shared.
- Example: If you share `/photos` and `/docs`, users will see two folders: `photos` and `docs` at the top level.
- **Use this if:** You want to share multiple folders and keep them separate.

### 5.3 Physical (Single Directory)

- Lets you share one folder as the root of the FTP server.
- Users can add, edit, or delete files and folders directly inside this root folder.
- Example: If you share `/home/user/ftp_root`, users will see all files and folders inside `ftp_root` and can manage them freely.
- **Use this if:** You want to share everything inside a single folder and allow full access within it.

### 5.4 Choosing a Backend

- Use **VirtualFileOperations** if you want to expose multiple directories as top-level folders or need to restrict access to specific directories.
- Use **PhysicalFileOperations** for direct, simple access to a single directory tree, with no virtual mapping, and if you need to allow operations at the root directory.

### 5.5 Key Points

- Both implementations **enforce boundaries**: you cannot access or modify files outside the allowed root(s).
- **Neither implementation allows deleting the root directory** (`/`). Attempting to do so will throw an error.
- **VirtualFileOperations** is stricter: it prevents any file or directory creation, deletion, or writing directly at the virtual root (`/`).
- **PhysicalFileOperations** allows creating and writing files at its root, but not deleting it (the root is the directory you provided, not the system root).

---

## 6. Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your changes. Make sure to follow the existing code style and include tests for new features.

---

## 7. License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
