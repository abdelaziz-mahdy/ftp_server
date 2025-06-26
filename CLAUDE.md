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
dart analyze                 # Run static analysis (configured via analysis_options.yaml)
dart format .                # Format all Dart code
```

### Dependencies
```bash
dart pub get                 # Install dependencies
dart pub upgrade             # Upgrade dependencies
dart pub deps                # Show dependency tree
```

### Example Usage
```bash
cd example                   # Navigate to example project
dart run                     # Run the example FTP server
```

## Project Architecture

### Core Components

1. **FtpServer** (`lib/ftp_server.dart`): Main server class that listens for connections and manages sessions
   - Handles socket binding and client connection management
   - Maintains list of active sessions for cleanup
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
- **Copy-on-Session**: FileOperations are copied per session to maintain isolation

### Server Configuration

The server supports two modes via `ServerType` enum:
- `ServerType.readOnly`: Disables write operations (STOR, DELE, MKD, RMD)
- `ServerType.readAndWrite`: Allows all operations

Authentication is optional - if username/password are provided, clients must authenticate.

### Testing Structure

Tests are organized by functionality:
- `test/ftp_server_test.dart`: Integration tests for the main server
- `test/file_operations/`: Unit tests for file system backends
- `test/platform_output_handler/`: Platform-specific output handling tests

### Error Handling

The codebase implements comprehensive error handling:
- Socket errors during data transfers are caught and handled gracefully
- File system operations include proper exception handling
- Transfer operations support abort functionality
- Logging is integrated throughout for debugging