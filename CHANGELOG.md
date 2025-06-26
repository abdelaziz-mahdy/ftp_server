
# Changelog

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
