
# Changelog

## 2.3.1

- Updated README with comprehensive documentation for all features
- Updated package description

## 2.3.0

### FTPS Support (RFC 4217 / RFC 2228)
- **Explicit FTPS**: `AUTH TLS`/`AUTH TLS-C` upgrade on standard port
- **Implicit FTPS**: TLS from connection start via `SecureServerSocket`
- **Data channel encryption**: `PROT P` (private) and `PROT C` (clear) with configurable enforcement
- New commands: `AUTH`, `PBSZ`, `PROT`, `CCC`
- `TlsConfig` class for certificate configuration (PEM files or pre-built `SecurityContext`)
- Mutual TLS (client certificate) support via `requireClientCert`
- `FEAT` advertises `AUTH TLS`, `PBSZ`, `PROT` when TLS configured
- `requireEncryptedData` option (defaults to `true` for implicit mode)
- Known limitations:
  - `CCC` returns 534 — Dart's `SecureSocket` cannot be unwrapped to plain TCP
  - `REIN` returns 502 under TLS — same Dart limitation
  - FileZilla (GnuTLS) may warn "TLS connection was non-properly terminated" on data connections — this is a client-side GnuTLS issue; the server sends close_notify correctly and data transfers complete successfully

## 2.2.0

This release focuses on **RFC compliance** and **stability**. The server now follows RFC 959, RFC 2389, RFC 2428, and RFC 3659 for all implemented commands.

### RFC Compliance Fixes
- `RETR` now validates file existence before opening data connection (no orphaned 150 replies)
- `STOR`, `RETR`, `CWD`, `DELE`, `RMD`, `SIZE`, `MDTM` return 501 for empty arguments
- `MKD` 257 response now contains the absolute FTP path (not relative)
- `CWD`/`CDUP` 250 response uses virtual FTP path (no physical path leakage)
- `PASS` now works with username-only or password-only server configurations
- `USER` sends 230 directly for no-auth servers (clients can skip PASS)
- `FEAT` no longer lists `PASV` (base RFC 959 command, not an extension per RFC 2389)
- `EPSV ALL` now enforced — `PORT`/`PASV` refused after `EPSV ALL` (RFC 2428 §4)
- `EPSV` validates network protocol argument; returns 522 for unsupported protocols (RFC 2428 §3)
- `PORT` validates all byte values are 0–255 (501 on invalid syntax)
- `ABOR` replies 225 when data connection open but no transfer in progress (RFC 959 §5.4)
- `MLSD` omits `size` fact for directory entries (RFC 3659 §7.5.5)
- `LIST -la` / `LIST -a` flags are stripped before directory lookup

### Bug Fixes
- Fixed unhandled `SocketException` crashes when clients disconnect during transfers (#15)
- Fixed `OPTS UTF8` crash when sent without ON/OFF argument
- Fixed passive socket file descriptor leak when clients send multiple PASV/EPSV commands
- Fixed session list memory leak — sessions now auto-remove on disconnect
- Fixed fire-and-forget async in MKD, RMD, DELE, RNTO, RENAME handlers — all now properly awaited
- Fixed `handleRnto` rethrowing exceptions without sending response to client
- Fixed `_getIpAddress` only matching 192.x.x.x networks — now supports 10.x and 172.x, and prefers control socket address
- Fixed pipelined commands (multiple commands in one TCP segment) being silently dropped
- Fixed `waitForClientDataSocket` crash when passive listener is closed before client connects

### New Commands
- `NLST` — returns bare filenames only, separated from LIST (was aliased to LIST)
- `HELP` — returns list of all supported commands
- `STAT` — returns server status
- `STRU` — accepts F (File), rejects others with 504
- `MODE` — accepts S (Stream), rejects others with 504
- `ALLO` — validates byte count and optional `R <record-size>` syntax (RFC 959)
- `ACCT` — accepts account string, returns 202 (superfluous); allowed pre-auth
- `REIN` — full session reinitialize: resets auth, CWD, data connections, pending state
- `SITE` — returns 501/502 with proper syntax validation

### Improvements
- Authentication enforcement: commands require login when credentials are configured
- `TYPE` now accepts `TYPE A N` form (ASCII Non-print) per RFC 959
- `FEAT` now advertises MLSD capability
- Error responses sanitized — no server path or exception leakage to clients
- `activeSessions` now returns unmodifiable list
- Async command queue ensures sequential processing of pipelined commands

### Internal API Changes
- `FTPCommandHandler` constructor no longer takes `controlSocket` (it was unused — all communication goes through the session)
- `FTPCommandHandler.handleCommand` is now `async` to properly await all operations
- `FtpSession.handleMlsd` and `handleMdtm` no longer take an extra `session` parameter
- Added `FtpSession.reinitialize()` for clean REIN implementation
- Added `FtpSession.epsvAllMode` flag for EPSV ALL enforcement

## 2.1.1
- Updated README documentation to include new rename commands

## 2.1.0

- Added RNFR/RNTO and RENAME commands for file and directory renaming
- Support for both PhysicalFileOperations and VirtualFileOperations


## 2.0.0

- Added `PhysicalFileOperations` for direct access to a single physical root directory, with no virtual mapping.
- `PhysicalFileOperations` allows writing, creating, and deleting files/directories at the root directory. This is the main difference from `VirtualFileOperations`, which does NOT allow writing to the virtual root (`/`).
- Updated documentation and tests to cover both file operation backends, their differences, and their limitations.
- Users can now choose between virtual mapping (multiple mapped roots) and direct physical access (single root) depending on their use case.

- BREAKING: The `sharedDirectories` parameter is removed from FtpServer. To use shared directories, users must now create a `VirtualFileOperations` instance with their desired directories and pass it to the `fileOperations` parameter. See the README for updated usage and migration instructions.
- BREAKING: The `startingDirectory` parameter is removed from FtpServer. The starting directory is now handled by the `FileOperations` instance (either `VirtualFileOperations` or `PhysicalFileOperations`). Both backends now accept a `startingDirectory` parameter in their constructors to control the initial directory.

## 1.0.7

- Improve pub points
- Update deps versions

## 1.0.6+1

- Fixing ChangeLog Styling

## 1.0.6

- Added a getter for getting a list of active sessions

## 1.0.5

- Fix: Active sessions are not terminated when calling `_server?.stop();` by [kkerimov](https://github.com/kkerimov)

## 1.0.4

- Adding MLSD,MDTM

## 1.0.3

- Android fix ip address
- Fix race condition for passive transfer
- Added UTF8 to Feat command

## 1.0.2

- Remove flutter test Dependency

## 1.0.1

- Fix Readme.

## 1.0.0

### Breaking Changes

- **Virtual File System**: Replaced `allowedDirectories` with `sharedDirectories` for better directory management under a virtual root. All directories specified in `sharedDirectories` are now shared under a virtual root, providing a unified view of multiple directories to the FTP clients.

- **Removed Flutter Dependency**: The server now runs directly on Dart, removing the need for Flutter and making it lighter.

### Enhancements

- **Improved Error Handling**: Added more robust error messages and safeguards for file operations.

- **Removed Legacy Code**: Cleaned up old path handling logic, streamlining file operations with the new virtual file system.

## 0.0.7

- update dependencies

## 0.0.6

- linux fix hang and test cases fixes thanks to [lawnvi](https://github.com/lawnvi) pr [#4](https://github.com/abdelaziz-mahdy/ftp_server/pull/4)

## 0.0.5

- General cleanup and fixes
- Implemented Feat and mspv
- path fixes and Implemented the UTF-8 option. thanks to [lawnvi](https://github.com/lawnvi) pr [#3](https://github.com/abdelaziz-mahdy/ftp_server/pull/3)

## 0.0.4

- Permission and full path fixes update fullpath method & add permission for example app [#1](https://github.com/abdelaziz-mahdy/ftp_server/pull/1) by [lawnvi](https://github.com/lawnvi) and implement PWD
- Added logger method to allow custom logs handling
- Added server startInBackground method
- General cleanup and adding test cases

## 0.0.3

- Refactored to allow custom logs

## 0.0.2

- Added CDUP command

## 0.0.1+1

- update readme

## 0.0.1

- initial release.
