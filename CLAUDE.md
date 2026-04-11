# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
```bash
dart test                    # Run all tests
dart test test/ftp_server_test.dart    # Run specific test file
dart test test/file_operations/        # Run file operations tests
```

### Code Quality
```bash
dart analyze                            # Run static analysis (configured via analysis_options.yaml)
dart format --set-exit-if-changed .     # Matches CI: fails if any file needs reformatting
```

**CI gate:** `.github/workflows/ci.yml` runs `flutter analyze`, `flutter test`, and `dart format --set-exit-if-changed .` on Linux/macOS/Windows. A local `dart format .` silently reformats — use `--set-exit-if-changed` before pushing, or CI will reject an otherwise-valid PR (this hit PR #29).

### Dependencies
```bash
dart pub get                 # Install dependencies
dart pub upgrade             # Upgrade dependencies
dart pub deps                # Show dependency tree
```

### Example Usage
```bash
cd example
flutter pub get
flutter run                  # example/ is a Flutter app, not plain Dart
```

**Gotcha:** `dart analyze` at the repo root reports errors in `example/lib/main.dart` because the Flutter SDK isn't on the Dart-only analysis path. These are not real issues — run `dart analyze lib test` to analyze just the package, or `flutter analyze` from inside `example/`.

## Project Architecture

### Core Components

1. **FtpServer** (`lib/ftp_server.dart`): Main server class that listens for connections and manages sessions
   - Handles socket binding and client connection management
   - Sessions auto-remove from `activeSessions` on disconnect — do **not** manually remove (2.2.0 fixed a leak caused by manual cleanup paths)
   - Supports both blocking (`start()`) and non-blocking (`startInBackground()`) modes

2. **FtpSession** (`lib/ftp_session.dart`): Manages individual client sessions
   - Handles authentication, data connections (passive/active modes)
   - Implements file transfer operations (RETR/STOR) with proper error handling
   - Manages FTP directory navigation and file listing

3. **FTPCommandHandler** (`lib/ftp_command_handler.dart`): Processes FTP protocol commands
   - Implements standard FTP commands (USER, PASS, LIST, RETR, STOR, etc.)
   - Enforces read-only mode restrictions when configured
   - Handles both standard and extended FTP commands

4. **FileOperations Interface** (`lib/file_operations/file_operations.dart`): Abstract interface for file system operations
   - Provides pluggable backend architecture
   - Handles path resolution and security boundaries
   - Supports both physical and virtual file system implementations

5. **TlsConfig** (`lib/tls_config.dart`): FTPS / TLS configuration (added in 2.3.0)
   - `FtpSecurityMode` enum: `none` (plain FTP), `explicit` (AUTH TLS on the standard port), `implicit` (TLS from connect, typically port 990)
   - `ProtectionLevel` enum: `clear` / `private_` — set via `PROT C` / `PROT P` (RFC 4217 §9)
   - Accepts either PEM file paths (`certFilePath` + `keyFilePath`) or a pre-built `SecurityContext`
   - Supports mutual TLS via `requireClientCert` + `trustedCertificatesPath`
   - `lib/ftp_server.dart` re-exports this file — users import from `package:ftp_server/ftp_server.dart`

6. **pasv_ip_selector** (`lib/src/pasv_ip_selector.dart`): Pure function picking the local IPv4 address advertised in PASV/EPSV responses. Extracted so it can be unit-tested without real sockets. Priority: control-socket address → `wlan0` → `en0` → `192.168.*` → `172.*` → `10.*`.

### File System Backends

- **PhysicalFileOperations** (`lib/file_operations/physical_file_operations.dart`): Direct file system access
  - Maps FTP root to a single physical directory
  - Allows full operations within the root directory
  
- **VirtualFileOperations** (`lib/file_operations/virtual_file_operations.dart`): Virtual file system
  - Maps multiple physical directories to virtual root folders
  - Restricts operations at the virtual root level
  - Provides isolation between different shared directories

### Key Design Patterns

- **Strategy Pattern**: FileOperations interface allows switching between different file system backends
- **Session Management**: Each client connection gets its own isolated session with state
- **Command Pattern**: FTP commands are handled through a centralized command handler
- **Copy-on-Session**: `FileOperations` is copied per session because it carries instance state (`currentDirectory`) — sharing would leak one client's CWD to another

### Code Layout Conventions

- **`lib/*.dart`** — public API. Importable as `package:ftp_server/<file>.dart` and part of the supported surface.
- **`lib/src/*.dart`** — implementation details. Importable from tests via `package:ftp_server/src/<file>.dart`, but **not** part of the public API and may change without a semver bump. Use this when you need to extract pure logic for unit testing without exposing it publicly (see `lib/src/pasv_ip_selector.dart`).
- **`lib/file_operations/`** — public subtree; the `FileOperations` interface is extensible by users (custom backends).
- **`lib/exceptions/`** — reserved for exception types; currently empty.

### Server Configuration

The server supports two modes via `ServerType` enum:
- `ServerType.readOnly`: Disables write operations (STOR, DELE, MKD, RMD)
- `ServerType.readAndWrite`: Allows all operations

Authentication is optional - if username/password are provided, clients must authenticate.

### Testing Structure

Tests split into **integration** (run a real `FtpServer` on a loopback port, talk to it via a client) and **unit** (pure logic, no sockets).

**Integration:**
- `test/ftp_server_test.dart` — server lifecycle, PASV/PORT/LIST/RETR/STOR/CWD
- `test/ftp_commands_test.dart` — RFC 959/2389/2428/3659 command-by-command conformance
- `test/ftps_test.dart` — FTPS handshake (explicit + implicit), `PROT P` enforcement. Uses PEM fixtures at `test/test_certs/{cert,key}.pem` (declared under `false_secrets` in `pubspec.yaml`)

**Unit:**
- `test/tls_config_test.dart` — `TlsConfig` construction + PEM loading
- `test/pasv_ip_selector_test.dart` — PASV IP priority rules (no sockets)
- `test/file_operations/` — `PhysicalFileOperations` / `VirtualFileOperations` / path resolvers (5 files)
- `test/platform_output_handler/` — LIST output normalization (mac/linux/windows variants)

Current suite: **246 tests**. CI runs them on Linux/macOS/Windows via `flutter test` — note that `flutter test` requires the Flutter SDK even though this is a pure Dart package, because CI is pinned to `subosito/flutter-action@v2`. Locally, `dart test` works identically.

### Adding a new FTP command

1. Add a case in `lib/ftp_command_handler.dart` (the switch in `handleCommand`).
   - Enforce read-only via the existing guard if the command mutates state
   - Return `501` on empty/invalid arguments before dispatching
2. Implement the handler method on `FtpSession` in `lib/ftp_session.dart`.
   - Send responses via `sendResponse('NNN text')` — use the RFC 959 code that matches (150 data open, 226 complete, 250 action ok, 501 syntax, 550 file unavailable, etc.)
   - Log via `logger.generalLog(...)` for diagnostics
3. If the command is an RFC 2389 extension, add it to the `FEAT` reply — do **not** add base RFC 959 commands; `FEAT` lists extensions only.
4. Add an entry to `test/ftp_commands_test.dart` covering at least: happy path, empty-argument → 501, and read-only-mode rejection (if applicable).

### Data-transfer error invariant

Socket errors or client aborts during `RETR` / `STOR` must **never** leave the control socket in a bad state. Always send a terminal response (`226` success / `426` aborted / `550` file error) before closing the data socket — see the `try/finally` blocks around `transferInProgress` in `ftp_session.dart` for the pattern. This was a recurring crash class through 2.2.0 (see CHANGELOG bug fixes); don't reintroduce it.