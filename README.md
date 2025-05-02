# Dart FTP Server

This package provides a simple FTP server implementation in Dart. It supports both read-only and read-and-write modes, making it suitable for various use cases. The server allows clients to connect and perform standard FTP operations such as listing directories, retrieving files, storing files, and more.

## Features

- **Passive and Active Modes**: Supports both passive and active data connections.
- **File Operations**: Retrieve, store, delete, and list files.
- **Directory Operations**: Change, make, and remove directories.
- **Read-Only Mode**: Disable write operations for enhanced security.
- **Authentication**: Basic username and password authentication.

## Compatibility

This package has been tested on macOS. For Linux and Windows, CI/CD test cases have been implemented to ensure the code runs and functions without any problems.

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
> - All directory logic (e.g., shared directories) is now handled by the provided `FileOperations` instance.
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

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your changes. Make sure to follow the existing code style and include tests for new features.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

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

## Limitations

- Both implementations prevent operations outside their allowed root(s).
- Only VirtualFileOperations prevents writing to the root directory itself for safety and consistency. PhysicalFileOperations allows it.
- In PhysicalFileOperations, `/` always refers to the root you provided, not the system root.

## Using with the FTP Server

The FTP server **requires** you to provide a `FileOperations` backend (such as `VirtualFileOperations` or `PhysicalFileOperations`) via the `fileOperations` parameter. This gives you full control over which directories are exposed and how file operations are handled.

- To expose multiple directories as top-level folders, use `VirtualFileOperations` and pass your shared directories to it.
- To expose a single directory tree (with `/` as the root), use `PhysicalFileOperations`.

**Migration Guide:**

- Replace any usage of `sharedDirectories` in your `FtpServer` constructor with a `fileOperations` parameter.
- Example migration:

  ```dart
  // Old:
  // final server = FtpServer(
  //   port: 21,
  //   sharedDirectories: ['/dir1', '/dir2'],
  //   ...
  // );

  // New:
  final fileOps = VirtualFileOperations(['/dir1', '/dir2']);
  final server = FtpServer(
    21,
    fileOperations: fileOps,
    ...
  );
  ```

See the code and tests for detailed usage examples and edge case handling.
