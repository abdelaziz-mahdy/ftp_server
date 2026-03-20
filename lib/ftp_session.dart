import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/tls_config.dart';
import 'package:intl/intl.dart';
import 'ftp_command_handler.dart';
import 'logger_handler.dart';
import 'file_operations/file_operations.dart';

class FtpSession {
  Socket _controlSocket;
  Socket get controlSocket => _controlSocket;

  bool isAuthenticated = false;
  final FTPCommandHandler commandHandler;
  ServerSocket? dataListener;
  SecureServerSocket? _secureDataListener;
  Socket? dataSocket;
  final String? username;
  final String? password;
  String? cachedUsername;
  String? pendingRenameFrom;

  final FileOperations fileOperations;
  final ServerType serverType;
  final LoggerHandler logger;
  bool transferInProgress = false;
  Future? _gettingDataSocket;

  /// RFC 2428: after EPSV ALL, PORT/PASV/LPRT must be refused.
  bool epsvAllMode = false;

  // --- TLS state ---

  /// Whether the control connection is TLS-encrypted.
  bool tlsActive;

  /// Whether PBSZ has been received (gate for PROT).
  bool pbszReceived;

  /// Data channel protection level.
  ProtectionLevel protectionLevel;

  /// SecurityContext for upgrading sockets (control and data).
  final SecurityContext? securityContext;

  /// Whether the server requires encrypted data connections.
  final bool requireEncryptedData;

  /// The security mode for this session.
  final FtpSecurityMode securityMode;

  /// Callback invoked when this session's connection is closed.
  /// Used by FtpServer to remove the session from its active list.
  void Function()? onDisconnect;

  FtpSession(
    this._controlSocket, {
    this.username,
    this.password,
    required FileOperations fileOperations,
    required this.serverType,
    required this.logger,
    this.securityContext,
    this.securityMode = FtpSecurityMode.none,
    this.requireEncryptedData = false,
    this.tlsActive = false,
    this.onDisconnect,
  })  : fileOperations = fileOperations.copy(),
        commandHandler = FTPCommandHandler(logger),
        pbszReceived = tlsActive,
        protectionLevel =
            tlsActive ? ProtectionLevel.private_ : ProtectionLevel.clear {
    sendResponse('220 Welcome to the FTP server');
    logger.generalLog('FtpSession created. Ready to process commands.');
    _attachControlListener();
  }

  void _attachControlListener() {
    _controlSocket.listen(
      processCommand,
      onDone: closeConnection,
      onError: (error) {
        logger.generalLog('Control socket error: $error');
        closeConnection();
      },
    );
  }

  /// Upgrade the control connection to TLS using SecureSocket.secureServer().
  /// Re-attaches the command listener on the new secure socket.
  Future<void> upgradeToTls() async {
    final secureSocket = await SecureSocket.secureServer(
      _controlSocket,
      securityContext!,
    );
    _controlSocket = secureSocket;
    _attachControlListener();
  }

  final StringBuffer _commandBuffer = StringBuffer();
  final List<String> _pendingCommands = [];
  bool _processing = false;

  void processCommand(List<int> data) {
    try {
      _commandBuffer.write(utf8.decode(data));
      final raw = _commandBuffer.toString();
      final lines = raw.split('\r\n');
      // Keep the last (potentially incomplete) fragment in the buffer
      _commandBuffer.clear();
      _commandBuffer.write(lines.last);
      for (final line in lines.sublist(0, lines.length - 1)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        _pendingCommands.add(trimmed);
      }
      _processQueue();
    } catch (e, s) {
      logger.generalLog("error: $e stack: $s ,input bytes $data");
      sendResponse('500 Internal server error');
    }
  }

  /// Processes queued commands one at a time.
  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_pendingCommands.isNotEmpty) {
        final command = _pendingCommands.removeAt(0);
        try {
          await commandHandler.handleCommand(command, this);
        } catch (e, s) {
          logger.generalLog("error: $e stack: $s");
          sendResponse('500 Internal server error');
        }
      }
    } finally {
      _processing = false;
    }
  }

  /// Reinitialize the session to its initial state (RFC 959 REIN).
  /// Resets authentication, transfer parameters, data connections, and
  /// working directory. If a transfer is in progress, data connections
  /// are left open until the transfer completes naturally.
  void reinitialize() {
    isAuthenticated = false;
    cachedUsername = null;
    pendingRenameFrom = null;
    epsvAllMode = false;

    // Reset TLS negotiation state (but NOT tlsActive, securityContext,
    // securityMode, requireEncryptedData — those are connection-level).
    pbszReceived = false;
    protectionLevel = ProtectionLevel.clear;

    // Reset working directory to root
    fileOperations.currentDirectory = fileOperations.rootDirectory;

    if (!transferInProgress) {
      // Only close data connections if no transfer is active.
      // RFC 959: "allow any transfer in progress to be completed"
      try {
        dataSocket?.close();
      } catch (_) {}
      try {
        dataListener?.close();
      } catch (_) {}
      try {
        _secureDataListener?.close();
      } catch (_) {}
      dataSocket = null;
      dataListener = null;
      _secureDataListener = null;
      _gettingDataSocket = null;
    }
    // If a transfer IS in progress, data connections remain open.
    // They will be cleaned up when the transfer completes.
  }

  void sendResponse(String message) {
    logger.logResponse(message);
    try {
      _controlSocket.write('$message\r\n');
    } catch (e) {
      logger.generalLog('Error sending response: $e');
    }
  }

  void closeConnection() {
    try {
      _controlSocket.close();
    } catch (e) {
      logger.generalLog('Error closing control socket: $e');
    }
    try {
      dataSocket?.close();
    } catch (e) {
      logger.generalLog('Error closing data socket: $e');
    }
    try {
      dataListener?.close();
    } catch (e) {
      logger.generalLog('Error closing data listener: $e');
    }
    try {
      _secureDataListener?.close();
    } catch (e) {
      logger.generalLog('Error closing secure data listener: $e');
    }
    dataSocket = null;
    dataListener = null;
    _secureDataListener = null;
    logger.generalLog('Connection closed');
    onDisconnect?.call();
  }

  /// Check whether a data transfer is allowed given the current PROT setting.
  /// Returns true if allowed, false if denied (and sends 521 response).
  bool checkDataProtection() {
    if (requireEncryptedData && protectionLevel != ProtectionLevel.private_) {
      sendResponse(
          '521 Data connection cannot be opened with current PROT setting');
      return false;
    }
    return true;
  }

  Future<bool> openDataConnection() async {
    try {
      await _gettingDataSocket;
    } catch (e) {
      logger.generalLog('Error while waiting for data socket: $e');
    }
    if (dataSocket == null) {
      sendResponse('425 Can\'t open data connection');
      return false;
    }
    sendResponse('150 Opening data connection');
    return true;
  }

  Future<void> waitForClientDataSocket({Duration? timeout}) {
    Future<Socket> result;
    if (_secureDataListener != null) {
      var secureResult = _secureDataListener!.first;
      if (timeout != null) {
        secureResult = secureResult.timeout(timeout, onTimeout: () {
          throw TimeoutException(
              'Timeout reached while waiting for client data socket');
        });
      }
      result = secureResult;
    } else {
      var plainResult = dataListener!.first;
      if (timeout != null) {
        plainResult = plainResult.timeout(timeout, onTimeout: () {
          throw TimeoutException(
              'Timeout reached while waiting for client data socket');
        });
      }
      result = plainResult;
    }
    return result.then((value) {
      dataSocket = value;
    }).catchError((Object e) {
      // dataListener was closed before a client connected (e.g. session ended)
      logger.generalLog('Data connection wait cancelled: $e');
    });
  }

  Future<void> enterPassiveMode() async {
    try {
      // Close any previous passive listener to avoid leaking sockets
      dataListener?.close();
      dataListener = null;
      _secureDataListener?.close();
      _secureDataListener = null;
      dataSocket?.close();
      dataSocket = null;

      if (protectionLevel == ProtectionLevel.private_ &&
          securityContext != null) {
        _secureDataListener = await SecureServerSocket.bind(
          InternetAddress.anyIPv4,
          0,
          securityContext!,
        );
        int port = _secureDataListener!.port;
        int p1 = port >> 8;
        int p2 = port & 0xFF;
        var address = (await _getIpAddress()).replaceAll('.', ',');
        sendResponse('227 Entering Passive Mode ($address,$p1,$p2)');
      } else {
        dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
        int port = dataListener!.port;
        int p1 = port >> 8;
        int p2 = port & 0xFF;
        var address = (await _getIpAddress()).replaceAll('.', ',');
        sendResponse('227 Entering Passive Mode ($address,$p1,$p2)');
      }

      _gettingDataSocket =
          waitForClientDataSocket(timeout: Duration(seconds: 30));
    } catch (e) {
      if (e is TlsException || e is HandshakeException) {
        sendResponse('522 TLS negotiation failed on data connection');
        logger.generalLog('TLS negotiation failed on data connection: $e');
      } else {
        sendResponse('425 Can\'t enter passive mode');
        logger.generalLog('Error entering passive mode: $e');
      }
    }
  }

  Future<void> enterActiveMode(String parameters) async {
    try {
      List<String> parts = parameters.split(',');
      if (parts.length < 6) {
        sendResponse('501 Syntax error in PORT parameters');
        return;
      }
      // Validate all 6 parts are valid byte values (0-255)
      final values = <int>[];
      for (final part in parts.take(6)) {
        final v = int.tryParse(part.trim());
        if (v == null || v < 0 || v > 255) {
          sendResponse('501 Syntax error in PORT parameters');
          return;
        }
        values.add(v);
      }
      String ip = values.take(4).join('.');
      int port = values[4] * 256 + values[5];

      if (protectionLevel == ProtectionLevel.private_ &&
          securityContext != null) {
        dataSocket = await SecureSocket.connect(
          ip,
          port,
          context: securityContext!,
        );
      } else {
        dataSocket = await Socket.connect(ip, port);
      }
      sendResponse('200 Active mode connection established');
    } catch (e) {
      if (e is TlsException || e is HandshakeException) {
        sendResponse('522 TLS negotiation failed on data connection');
        logger.generalLog('TLS negotiation failed on data connection: $e');
      } else {
        sendResponse('425 Can\'t enter active mode');
        logger.generalLog('Error entering active mode: $e');
      }
    }
  }

  Future<String> _getIpAddress() async {
    // Use the control socket's local address if available
    try {
      final addr = _controlSocket.address;
      if (addr.type == InternetAddressType.IPv4 &&
          !addr.isLoopback &&
          addr.address != '0.0.0.0') {
        return addr.address;
      }
    } catch (_) {}

    // Fallback: scan network interfaces for a private IPv4 address
    try {
      final networkInterfaces = await NetworkInterface.list();
      final ipList = networkInterfaces
          .map((interface) => interface.addresses)
          .expand((ip) => ip)
          .where((ip) =>
              ip.type == InternetAddressType.IPv4 &&
              !ip.isLoopback &&
              !ip.isLinkLocal)
          .toList();

      if (ipList.isNotEmpty) {
        // Prefer private network addresses
        final privateIp = ipList.firstWhere(
          (address) =>
              address.address.startsWith('192.') ||
              address.address.startsWith('10.') ||
              address.address.startsWith('172.'),
          orElse: () => ipList.first,
        );
        return privateIp.address;
      }
    } catch (e) {
      logger.generalLog('Error getting IP address: $e');
    }
    return '0.0.0.0';
  }

  Future<void> listDirectory(String path) async {
    if (!checkDataProtection()) return;

    if (!await openDataConnection()) {
      return;
    }

    try {
      transferInProgress = true;

      var dirContents = await fileOperations.listDirectory(path);
      logger.generalLog(
          'Listing directory: $path, for ${fileOperations.resolvePath(path)} dir contents: $dirContents');

      for (FileSystemEntity entity in dirContents) {
        if (!transferInProgress) break;

        try {
          var stat = await entity.stat();
          String permissions = _formatPermissions(stat);
          String fileSize = stat.size.toString();
          String modificationTime = _formatModificationTime(stat.modified);
          String fileName = entity.path.split(Platform.pathSeparator).last;
          String entry =
              '$permissions 1 ftp ftp $fileSize $modificationTime $fileName\r\n';

          if (dataSocket == null || !transferInProgress) break;

          try {
            dataSocket!.write(entry);
          } catch (socketError) {
            logger.generalLog(
                'Socket write error during directory listing: $socketError');
            transferInProgress = false;
            break;
          }
        } catch (entityError) {
          logger.generalLog(
              'Error processing entity during directory listing: $entityError');
          continue;
        }
      }

      if (transferInProgress) {
        transferInProgress = false;
        await _closeDataSocket();
        sendResponse('226 Transfer complete');
      } else {
        await _closeDataSocket();
        sendResponse('426 Transfer aborted');
      }
    } catch (e) {
      logger.generalLog('Error listing directory: $e');
      sendResponse('550 Failed to list directory');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

  /// NLST: list only filenames, one per line (RFC 959).
  Future<void> listDirectoryNames(String path) async {
    if (!checkDataProtection()) return;

    if (!await openDataConnection()) {
      return;
    }

    try {
      transferInProgress = true;
      var dirContents = await fileOperations.listDirectory(path);

      for (FileSystemEntity entity in dirContents) {
        if (!transferInProgress || dataSocket == null) break;

        try {
          String fileName = entity.path.split(Platform.pathSeparator).last;
          dataSocket!.write('$fileName\r\n');
        } catch (e) {
          logger.generalLog('Socket write error during NLST: $e');
          transferInProgress = false;
          break;
        }
      }

      if (transferInProgress) {
        transferInProgress = false;
        await _closeDataSocket();
        sendResponse('226 Transfer complete');
      } else {
        await _closeDataSocket();
        sendResponse('426 Transfer aborted');
      }
    } catch (e) {
      logger.generalLog('Error listing directory names: $e');
      sendResponse('550 Failed to list directory');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

  String _formatPermissions(FileStat stat) {
    String type = stat.type == FileSystemEntityType.directory ? 'd' : '-';
    String owner = _permissionToString(stat.mode >> 6);
    String group = _permissionToString((stat.mode >> 3) & 7);
    String others = _permissionToString(stat.mode & 7);
    return '$type$owner$group$others';
  }

  String _permissionToString(int permission) {
    String read = (permission & 4) != 0 ? 'r' : '-';
    String write = (permission & 2) != 0 ? 'w' : '-';
    String execute = (permission & 1) != 0 ? 'x' : '-';
    return '$read$write$execute';
  }

  String _formatModificationTime(DateTime dateTime) {
    return DateFormat('MMM dd HH:mm').format(dateTime);
  }

  Future<void> retrieveFile(String filename) async {
    if (filename.isEmpty) {
      sendResponse('501 Syntax error in parameters');
      return;
    }

    // Check file existence before opening data connection to avoid
    // sending 550 after 150 (RFC 959: validate before preliminary reply)
    if (!fileOperations.exists(filename)) {
      sendResponse('550 File not found');
      return;
    }
    String fullPath = fileOperations.resolvePath(filename);
    File file = File(fullPath);
    if (!await file.exists()) {
      sendResponse('550 File not found');
      return;
    }

    if (!checkDataProtection()) return;

    if (!await openDataConnection()) {
      return;
    }

    try {
      transferInProgress = true;

      if (await file.exists()) {
        Stream<List<int>> fileStream = file.openRead();

        StreamSubscription<List<int>>? subscription;
        subscription = fileStream.listen(
          (data) {
            if (transferInProgress && dataSocket != null) {
              try {
                dataSocket!.add(data);
              } catch (e) {
                logger.generalLog('Error writing to data socket: $e');
                transferInProgress = false;
                subscription?.cancel();
                _closeDataSocket();
              }
            }
          },
          onDone: () async {
            if (transferInProgress) {
              transferInProgress = false;
              await _closeDataSocket();
              sendResponse('226 Transfer complete');
            }
          },
          onError: (error) async {
            logger.generalLog('Error reading from file: $error');
            if (transferInProgress) {
              sendResponse('426 Connection closed; transfer aborted');
              transferInProgress = false;
              await _closeDataSocket();
            }
          },
          cancelOnError: true,
        );
      }
    } catch (e) {
      logger.generalLog('Exception in retrieveFile: $e');
      sendResponse('550 File transfer failed');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

  Future<void> storeFile(String filename) async {
    if (filename.isEmpty) {
      sendResponse('501 Syntax error in parameters');
      return;
    }

    if (!checkDataProtection()) return;

    if (!await openDataConnection()) {
      return;
    }

    File? file;
    IOSink? fileSink;

    try {
      String fullPath = fileOperations.resolvePath(filename);
      transferInProgress = true;

      final directory = Directory(fullPath).parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      file = File(fullPath);
      fileSink = file.openWrite();

      dataSocket!.listen(
        (data) {
          if (transferInProgress) {
            try {
              fileSink?.add(data);
            } catch (e) {
              logger.generalLog('Error writing to file: $e');
              _handleTransferError(fileSink);
            }
          }
        },
        onDone: () async {
          if (transferInProgress) {
            try {
              await fileSink?.flush();
              await fileSink?.close();
              transferInProgress = false;
              await _closeDataSocket();
              sendResponse('226 Transfer complete');
              logger
                  .generalLog('File transfer complete: $filename to $fullPath');
            } catch (e) {
              logger.generalLog('Error closing file after transfer: $e');
              _handleTransferError(fileSink);
            }
          }
        },
        onError: (error) async {
          logger.generalLog('Socket error during file upload: $error');
          _handleTransferError(fileSink);
        },
        cancelOnError: true,
      );
    } catch (e) {
      logger.generalLog('Exception in storeFile: $e');
      sendResponse('550 Error creating file or directory');
      transferInProgress = false;
      fileSink
          ?.close()
          .catchError((e) => logger.generalLog('Error closing file sink: $e'));
      await _closeDataSocket();
    }
  }

  void _handleTransferError(IOSink? fileSink) async {
    if (!transferInProgress) return; // Already aborted (e.g. by ABOR)
    sendResponse('426 Connection closed; transfer aborted');
    if (fileSink != null) {
      try {
        await fileSink.close();
      } catch (e) {
        logger.generalLog('Error closing file sink during error handling: $e');
      }
    }
    transferInProgress = false;
    await _closeDataSocket();
  }

  Future<void> _closeDataSocket() async {
    if (dataSocket != null) {
      try {
        await dataSocket!.flush().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            logger
                .generalLog('Socket flush timeout, closing socket forcefully');
            return;
          },
        );
      } catch (e) {
        logger.generalLog('Error flushing data socket: $e');
      }

      try {
        await dataSocket!.close();
      } catch (e) {
        logger.generalLog('Error closing data socket: $e');
      } finally {
        dataSocket = null;
      }
    }
  }

  void abortTransfer() async {
    if (transferInProgress) {
      transferInProgress = false;
      try {
        dataSocket?.destroy();
      } catch (e) {
        logger.generalLog('Error destroying data socket during abort: $e');
      }
      dataSocket = null;
      try {
        dataListener?.close();
      } catch (e) {
        logger.generalLog('Error closing data listener during abort: $e');
      }
      dataListener = null;
      try {
        _secureDataListener?.close();
      } catch (e) {
        logger
            .generalLog('Error closing secure data listener during abort: $e');
      }
      _secureDataListener = null;
      // RFC 959: ABOR during transfer requires 426 followed by 226
      sendResponse('426 Transfer aborted');
      sendResponse('226 ABOR command successful');
    } else {
      // RFC 959: 225 if data connection open but no transfer; 226 otherwise
      if (dataSocket != null || dataListener != null) {
        sendResponse('225 Data connection open; no transfer in progress');
      } else {
        sendResponse('226 ABOR command successful');
      }
    }
  }

  void changeDirectory(String dirname) {
    if (dirname.isEmpty) {
      sendResponse('501 Syntax error in parameters');
      return;
    }
    try {
      fileOperations.changeDirectory(dirname);
      sendResponse(
          '250 Directory changed to ${fileOperations.getCurrentDirectory()}');
    } catch (e) {
      sendResponse('550 Access denied or directory not found');
      logger.generalLog('Error changing directory: $e');
    }
  }

  void changeToParentDirectory() {
    try {
      fileOperations.changeToParentDirectory();
      sendResponse(
          '250 Directory changed to ${fileOperations.getCurrentDirectory()}');
    } catch (e) {
      sendResponse('550 Access denied or directory not found');
      logger.generalLog('Error changing to parent directory: $e');
    }
  }

  Future<void> makeDirectory(String dirname) async {
    if (dirname.isEmpty) {
      sendResponse('501 Syntax error in parameters');
      return;
    }
    try {
      await fileOperations.createDirectory(dirname);
      // RFC 959: 257 response must contain the absolute FTP pathname.
      // Temporarily change into the new dir to get its resolved virtual path,
      // then change back to the original directory.
      final savedDir = fileOperations.getCurrentDirectory();
      try {
        fileOperations.changeDirectory(dirname);
        final absPath = fileOperations.getCurrentDirectory();
        sendResponse('257 "$absPath" created');
      } finally {
        fileOperations.changeDirectory(savedDir);
      }
    } catch (e) {
      sendResponse('550 Failed to create directory');
      logger.generalLog('Error creating directory: $e');
    }
  }

  Future<void> removeDirectory(String dirname) async {
    if (dirname.isEmpty) {
      sendResponse('501 Syntax error in parameters');
      return;
    }
    try {
      await fileOperations.deleteDirectory(dirname);
      sendResponse('250 Directory deleted');
    } catch (e) {
      sendResponse('550 Failed to delete directory');
      logger.generalLog('Error deleting directory: $e');
    }
  }

  Future<void> deleteFile(String filePath) async {
    if (filePath.isEmpty) {
      sendResponse('501 Syntax error in parameters');
      return;
    }
    try {
      await fileOperations.deleteFile(filePath);
      sendResponse('250 File deleted');
    } catch (e) {
      sendResponse('550 Failed to delete file');
      logger.generalLog('Error deleting file: $e');
    }
  }

  Future<void> fileSize(String filePath) async {
    if (filePath.isEmpty) {
      sendResponse('501 Syntax error in parameters');
      return;
    }
    try {
      int size = await fileOperations.fileSize(filePath);
      sendResponse('213 $size');
    } catch (e) {
      sendResponse('550 Failed to get file size');
      logger.generalLog('Error getting file size: $e');
    }
  }

  Future<void> enterExtendedPassiveMode() async {
    try {
      // Close any previous passive listener to avoid leaking sockets
      dataListener?.close();
      dataListener = null;
      _secureDataListener?.close();
      _secureDataListener = null;
      dataSocket?.close();
      dataSocket = null;

      if (protectionLevel == ProtectionLevel.private_ &&
          securityContext != null) {
        _secureDataListener = await SecureServerSocket.bind(
          InternetAddress.anyIPv4,
          0,
          securityContext!,
        );
        int port = _secureDataListener!.port;
        sendResponse('229 Entering Extended Passive Mode (|||$port|)');
      } else {
        dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
        int port = dataListener!.port;
        sendResponse('229 Entering Extended Passive Mode (|||$port|)');
      }

      _gettingDataSocket =
          waitForClientDataSocket(timeout: Duration(seconds: 30));
    } catch (e) {
      if (e is TlsException || e is HandshakeException) {
        sendResponse('522 TLS negotiation failed on data connection');
        logger.generalLog('TLS negotiation failed on data connection: $e');
      } else {
        sendResponse('425 Can\'t enter extended passive mode');
        logger.generalLog('Error entering extended passive mode: $e');
      }
    }
  }

  Future<void> handleMlsd(String argument) async {
    if (!checkDataProtection()) return;

    if (!await openDataConnection()) {
      return;
    }

    try {
      transferInProgress = true;
      var dirContents = await fileOperations.listDirectory(argument);
      logger.generalLog('Listing directory with MLSD: $argument');

      for (FileSystemEntity entity in dirContents) {
        if (!transferInProgress || dataSocket == null) break;

        try {
          var stat = await entity.stat();
          String facts = _formatMlsdFacts(entity, stat);

          try {
            dataSocket!.write(facts);
          } catch (socketError) {
            logger.generalLog('Socket write error during MLSD: $socketError');
            transferInProgress = false;
            break;
          }
        } catch (entityError) {
          logger
              .generalLog('Error processing entity during MLSD: $entityError');
          continue;
        }
      }

      if (transferInProgress) {
        transferInProgress = false;
        await _closeDataSocket();
        sendResponse('226 Transfer complete.');
      } else {
        await _closeDataSocket();
        sendResponse('426 Transfer aborted');
      }
    } catch (e) {
      logger.generalLog('Error listing directory with MLSD: $e');
      sendResponse('550 Failed to list directory');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

  String _formatMlsdFacts(FileSystemEntity entity, FileStat stat) {
    final isDir = stat.type == FileSystemEntityType.directory;
    String type = isDir ? "dir" : "file";
    String modify = DateFormat("yyyyMMddHHmmss")
        .format(stat.modified.toUtc()); // Use UTC time
    String name = entity.path.split(Platform.pathSeparator).last;
    // RFC 3659 §7.5.5: size fact is undefined for directories, omit it
    String sizeFact = isDir ? '' : 'size=${stat.size};';

    return "type=$type;modify=$modify;$sizeFact $name\r\n";
  }

  void handleMdtm(String argument) {
    if (argument.isEmpty) {
      sendResponse('501 Syntax error in parameters');
      return;
    }
    try {
      if (!fileOperations.exists(argument)) {
        sendResponse('550 File not found');
        return;
      }

      String fullPath = fileOperations.resolvePath(argument);
      File file = File(fullPath);
      if (file.existsSync()) {
        var stat = file.statSync();
        String modificationTime = _formatMdtmTimestamp(stat.modified);
        sendResponse('213 $modificationTime');
      } else {
        sendResponse('550 File not found');
      }
    } catch (e) {
      sendResponse('550 Could not get modification time');
      logger.generalLog('Error getting modification time: $e');
    }
  }

  /// STAT with pathname: list file/directory info over the control connection
  /// (RFC 959 §4.1.3). Uses 213 for status replies sent over control.
  Future<void> statPath(String path) async {
    try {
      final dirContents = await fileOperations.listDirectory(path);
      sendResponse('213-Status of $path:');
      for (FileSystemEntity entity in dirContents) {
        try {
          var stat = await entity.stat();
          String permissions = _formatPermissions(stat);
          String fileSize = stat.size.toString();
          String modificationTime = _formatModificationTime(stat.modified);
          String fileName = entity.path.split(Platform.pathSeparator).last;
          sendResponse(
              ' $permissions 1 ftp ftp $fileSize $modificationTime $fileName');
        } catch (_) {
          continue;
        }
      }
      sendResponse('213 End of status');
    } catch (e) {
      // If path is a file, try to stat it directly
      try {
        String fullPath = fileOperations.resolvePath(path);
        File file = File(fullPath);
        if (await file.exists()) {
          var stat = await file.stat();
          String permissions = _formatPermissions(stat);
          String fileSize = stat.size.toString();
          String modificationTime = _formatModificationTime(stat.modified);
          String fileName = file.path.split(Platform.pathSeparator).last;
          sendResponse('213-Status of $path:');
          sendResponse(
              ' $permissions 1 ftp ftp $fileSize $modificationTime $fileName');
          sendResponse('213 End of status');
        } else {
          sendResponse('450 No such file or directory');
        }
      } catch (_) {
        sendResponse('450 No such file or directory');
      }
    }
  }

  String _formatMdtmTimestamp(DateTime dateTime) {
    return DateFormat('yyyyMMddHHmmss').format(dateTime.toUtc()); // Use UTC
  }

  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {
    try {
      await fileOperations.renameFileOrDirectory(oldPath, newPath);
      pendingRenameFrom = null;
      sendResponse('250 Requested file action completed successfully');
    } catch (e) {
      pendingRenameFrom = null;
      sendResponse('550 Failed to rename');
      logger.generalLog('Error renaming $oldPath to $newPath: $e');
    }
  }
}
