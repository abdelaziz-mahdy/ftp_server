

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

Here's an example of how to start the FTP server:

```dart
import 'package:ftp_server/ftp_server.dart';

void main() async {
  final server = FtpServer(
    port: 21,
    username: 'user',
    password: 'pass',
    sharedDirectories: ['/home/user/ftp'],
    startingDirectory: 'ftp',
    serverType: ServerType.readAndWrite, // or ServerType.readOnly
  );

  await server.start();
}
```

### Supported Operations

The server supports the following FTP commands:

| Command             | Description                                                      |
|---------------------|------------------------------------------------------------------|
| `USER <username>`   | Set the username for authentication.                             |
| `PASS <password>`   | Set the password for authentication.                             |
| `QUIT`              | Close the control connection.                                    |
| `PASV`              | Enter passive mode.                                              |
| `PORT <host-port>`  | Enter active mode.                                               |
| `LIST [<directory>]`| List files in the specified directory or current directory.      |
| `RETR <filename>`   | Retrieve the specified file.                                     |
| `STOR <filename>`   | Store a file.                                                    |
| `CWD <directory>`   | Change the current directory.                                    |
| `CDUP`              | Change to the parent directory.                                  |
| `MKD <directory>`   | Make a new directory.                                            |
| `RMD <directory>`   | Remove a directory.                                              |
| `DELE <filename>`   | Delete a file.                                                   |
| `PWD`               | Print the current directory.                                     |
| `SYST`              | Return system type.                                              |
| `NOOP`              | No operation (used to keep the connection alive).                |
| `SIZE <filename>`   | Return the size of the specified file.                           |

### Authentication

To enable authentication, provide the `username` and `password` parameters when creating the `FtpServer` instance. The server will then require clients to log in using these credentials.

### Read-Only Mode

To run the server in read-only mode, set the `serverType` parameter to `ServerType.readOnly`. In this mode, commands that modify the filesystem (e.g., `STOR`, `DELE`, `MKD`, `RMD`) will be disabled.

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your changes. Make sure to follow the existing code style and include tests for new features.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

