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
