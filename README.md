# Dart FTP Server

A standards-compliant FTP/FTPS server in Dart. Supports plain FTP and encrypted FTPS (explicit and implicit TLS), read-only and read-write modes, with pluggable file system backends.

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
   - [FTPS (TLS/SSL)](#46-ftps-tlsssl)
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
  final server = FtpServer(
    21,
    fileOperations: VirtualFileOperations(['/home/user/shared']),
    serverType: ServerType.readAndWrite,
  );

  await server.start();
}
```

That's it — an anonymous FTP server sharing a directory. Add `username`/`password` for authentication, or `securityMode`/`tlsConfig` for FTPS. See below for details.

---

## 2. Features

- **FTP and FTPS**: Plain FTP, explicit FTPS (AUTH TLS), and implicit FTPS
- **Passive and Active Modes**: Both passive (PASV/EPSV) and active (PORT) data connections
- **File Operations**: Retrieve, store, delete, rename, and list files
- **Directory Operations**: Change, make, remove, and list directories
- **Read-Only Mode**: Disable all write operations for security
- **Authentication**: Optional username/password with flexible credential configs
- **Pluggable Backends**: Virtual (multiple directories) or Physical (single root)
- **Standards Compliant**:
  - [RFC 959](https://www.rfc-editor.org/rfc/rfc959) — File Transfer Protocol (core)
  - [RFC 2228](https://www.rfc-editor.org/rfc/rfc2228) — FTP Security Extensions
  - [RFC 2389](https://www.rfc-editor.org/rfc/rfc2389) — Feature negotiation (FEAT/OPTS)
  - [RFC 2428](https://www.rfc-editor.org/rfc/rfc2428) — Extended passive mode (EPSV)
  - [RFC 3659](https://www.rfc-editor.org/rfc/rfc3659) — Extensions (MLST, MDTM, SIZE)
  - [RFC 4217](https://www.rfc-editor.org/rfc/rfc4217) — Securing FTP with TLS (FTPS)

---

## 3. Compatibility

Tested on **macOS**, **Linux**, and **Windows**. CI/CD runs 231 tests on all three platforms on every commit.

---

## 4. Usage

### 4.1 Starting the Server

#### Basic (anonymous, no auth)

```dart
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';

void main() async {
  final server = FtpServer(
    21,
    fileOperations: VirtualFileOperations(['/home/user/shared']),
    serverType: ServerType.readAndWrite,
  );
  await server.start();
}
```

#### With authentication

```dart
final server = FtpServer(
  21,
  username: 'admin',
  password: 'secret',
  fileOperations: VirtualFileOperations(['/home/user/shared']),
  serverType: ServerType.readAndWrite,
);
```

#### Using PhysicalFileOperations (single directory)

```dart
import 'package:ftp_server/file_operations/physical_file_operations.dart';

final server = FtpServer(
  21,
  fileOperations: PhysicalFileOperations('/home/user/ftp_root'),
  serverType: ServerType.readAndWrite,
);
```

### 4.2 Running in the Background

```dart
await server.startInBackground();
// Your app continues running while the FTP server handles connections
```

To stop:

```dart
await server.stop();
```

### 4.3 Supported FTP Commands

| Command | Description |
|---|---|
| **Authentication** | |
| `USER <username>` | Set username. Returns 230 directly if no auth configured. |
| `PASS <password>` | Set password. Supports username-only or password-only configs. |
| `ACCT <info>` | Account info (accepted, not required). |
| `REIN` | Reset session — logout without disconnecting. |
| `QUIT` | Close the connection. |
| **Directory Navigation** | |
| `PWD` | Print current directory (absolute FTP path). |
| `CWD <directory>` | Change directory. |
| `CDUP` | Change to parent directory. |
| `MKD <directory>` | Create directory. Response includes absolute path. |
| `RMD <directory>` | Remove directory. |
| **File Operations** | |
| `LIST [<path>]` | List files with details (permissions, size, date). |
| `NLST [<path>]` | List filenames only. |
| `MLSD [<path>]` | Machine-readable directory listing (RFC 3659). |
| `STAT [<path>]` | File/directory status over control connection. |
| `RETR <filename>` | Download a file. |
| `STOR <filename>` | Upload a file. |
| `DELE <filename>` | Delete a file. |
| `RNFR <filename>` | Rename from (start rename sequence). |
| `RNTO <filename>` | Rename to (complete rename sequence). |
| `SIZE <filename>` | Get file size in bytes. |
| `MDTM <filename>` | Get last modification time (UTC). |
| **Data Connection** | |
| `PASV` | Enter passive mode. |
| `EPSV [<protocol>]` | Enter extended passive mode (RFC 2428). |
| `PORT <h1,h2,h3,h4,p1,p2>` | Enter active mode. |
| `ABOR` | Abort current transfer. |
| `TYPE <type>` | Set transfer type (A=ASCII, I=binary). |
| `STRU <code>` | Set file structure (F=file only). |
| `MODE <code>` | Set transfer mode (S=stream only). |
| `ALLO <bytes> [R <size>]` | Allocate storage (accepted, not required). |
| **Security (FTPS)** | |
| `AUTH TLS` | Upgrade control connection to TLS (explicit FTPS). |
| `PBSZ 0` | Set protection buffer size (required before PROT). |
| `PROT P\|C` | Set data protection: P=private (encrypted), C=clear. |
| `CCC` | Clear command channel (not supported — returns 534). |
| **Server Info** | |
| `SYST` | Return system type (UNIX Type: L8). |
| `FEAT` | List supported features and extensions. |
| `OPTS <option>` | Set options (e.g., `OPTS UTF8 ON`). |
| `HELP` | List all supported commands. |
| `NOOP` | No operation (keep-alive). |
| `SITE <cmd>` | Site-specific commands (not implemented — returns 502). |

### 4.4 Authentication

Authentication is **optional**. The server supports several configurations:

| Configuration | Behavior |
|---|---|
| No credentials | Anonymous access. `USER` returns 230 immediately. |
| Username + password | Both must match. `USER` returns 331, then `PASS` required. |
| Username only | Any password accepted if username matches. |
| Password only | Any username accepted if password matches. |

```dart
// Anonymous (no auth)
FtpServer(21, fileOperations: fileOps, serverType: serverType);

// Full credentials
FtpServer(21, username: 'admin', password: 'secret', ...);

// Username only (password ignored)
FtpServer(21, username: 'admin', ...);
```

When credentials are configured, commands like `LIST`, `RETR`, `STOR`, etc. require authentication. Pre-auth commands (`USER`, `PASS`, `QUIT`, `FEAT`, `SYST`, `NOOP`, `OPTS`, `AUTH`, `PBSZ`, `PROT`) always work.

### 4.5 Read-Only Mode

```dart
final server = FtpServer(
  21,
  fileOperations: fileOps,
  serverType: ServerType.readOnly, // STOR, DELE, MKD, RMD disabled
);
```

Write commands return `550 Command not allowed in read-only mode`.

### 4.6 FTPS (TLS/SSL)

The server supports FTPS per [RFC 4217](https://www.rfc-editor.org/rfc/rfc4217). Three security modes:

| Mode | Description | Typical Port |
|---|---|---|
| `FtpSecurityMode.none` | Plain FTP (default) | 21 |
| `FtpSecurityMode.explicit` | Plain connection, client upgrades via `AUTH TLS` | 21 |
| `FtpSecurityMode.implicit` | TLS from connection start | 990 |

#### Explicit FTPS

Client connects on a plain port and upgrades to TLS:

```dart
final server = FtpServer(
  21,
  fileOperations: fileOps,
  serverType: ServerType.readAndWrite,
  securityMode: FtpSecurityMode.explicit,
  tlsConfig: TlsConfig(
    certFilePath: '/path/to/cert.pem',
    keyFilePath: '/path/to/key.pem',
  ),
);
```

#### Implicit FTPS

All connections are TLS-encrypted from the start:

```dart
final server = FtpServer(
  990,
  fileOperations: fileOps,
  serverType: ServerType.readAndWrite,
  securityMode: FtpSecurityMode.implicit,
  tlsConfig: TlsConfig(
    certFilePath: '/path/to/cert.pem',
    keyFilePath: '/path/to/key.pem',
  ),
);
```

#### TLS Configuration Options

```dart
// Simple: PEM files
TlsConfig(
  certFilePath: 'cert.pem',
  keyFilePath: 'key.pem',
)

// Advanced: pre-built SecurityContext
TlsConfig(
  securityContext: myCustomContext,
)

// Mutual TLS (client certificates)
TlsConfig(
  certFilePath: 'cert.pem',
  keyFilePath: 'key.pem',
  requireClientCert: true,
  trustedCertificatesPath: 'ca.pem',
)
```

#### Enforcing Encrypted Data Channels

By default, clients choose whether to encrypt data channels (`PROT P` or `PROT C`). To require encryption:

```dart
FtpServer(
  21,
  fileOperations: fileOps,
  serverType: ServerType.readAndWrite,
  securityMode: FtpSecurityMode.explicit,
  tlsConfig: tlsConfig,
  requireEncryptedData: true, // Refuse PROT C, require PROT P
);
```

For implicit mode, `requireEncryptedData` is automatically set to `true`.

#### Known Limitations

- **CCC** (Clear Command Channel): Returns 534. Dart's `SecureSocket` cannot be downgraded to plain TCP.
- **REIN under TLS**: Returns 502. Same Dart limitation — TLS cannot be unwrapped.
- **FileZilla/GnuTLS**: May warn "TLS connection was non-properly terminated" on data channels. This is a client-side GnuTLS issue; data transfers complete successfully.

---

## 5. File Sharing Backends

### 5.1 Quick Comparison

| Feature | Virtual | Physical |
|---|---|---|
| Shared folders | Multiple | One |
| Write at root? | No | Yes |
| Root meaning | Virtual (not a real folder) | The actual folder |
| Best for | Sharing several separate folders | Sharing one folder tree |

### 5.2 Virtual (Multiple Directories)

Shares multiple folders as top-level directories. Users cannot modify the root `/` directly.

```dart
final fileOps = VirtualFileOperations([
  '/home/user/photos',
  '/home/user/documents',
]);
// Users see: /photos/ and /documents/
```

### 5.3 Physical (Single Directory)

Shares one folder as the FTP root. Users can create/delete files directly at root level.

```dart
final fileOps = PhysicalFileOperations('/home/user/ftp_root');
// Users see the contents of ftp_root directly
```

### 5.4 Choosing a Backend

- **VirtualFileOperations**: Multiple directories, restricted root, better isolation
- **PhysicalFileOperations**: Single directory, full root access, simpler

### 5.5 Key Points

- Both enforce boundaries — no access outside allowed root(s)
- Neither allows deleting the root directory
- VirtualFileOperations prevents writes at the virtual root `/`
- PhysicalFileOperations allows writes at root, but not deleting root itself

---

## 6. Contributing

Contributions are welcome! Please fork the repository and submit a pull request. Follow the existing code style and include tests for new features.

---

## 7. License

MIT License. See [LICENSE](LICENSE) for details.
