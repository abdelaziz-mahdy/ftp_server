import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/server_type.dart';
import 'package:intl/intl.dart';
import 'ftp_command_handler.dart';
import 'logger_handler.dart';
import 'file_operations/file_operations.dart';

class FtpSession {
  final Socket controlSocket;
  bool isAuthenticated = false;
  final FTPCommandHandler commandHandler;
  ServerSocket? dataListener;
  Socket? dataSocket;
  final String? username;
  final String? password;
  String? cachedUsername;

  final FileOperations fileOperations;
  final List<String> sharedDirectories;
  final ServerType serverType;
  final LoggerHandler logger;
  bool transferInProgress = false;
  Future? _gettingDataSocket;
  String get currentDirectory => fileOperations.getCurrentDirectory();

  FtpSession(this.controlSocket,
      {this.username,
      this.password,
      required this.sharedDirectories,
      required this.serverType,
      required this.logger,
      String? startingDirectory})
      : commandHandler = FTPCommandHandler(controlSocket, logger),
        fileOperations = VirtualFileOperations(sharedDirectories,
            startingDirectory: startingDirectory ?? '/') {
    sendResponse('220 Welcome to the FTP server');
    logger.generalLog(
        'FtpSession created. Attempting to set starting directory.'); // Log session creation

    controlSocket.listen(processCommand, onDone: closeConnection);
  }

  void processCommand(List<int> data) {
    try {
      String commandLine = utf8.decode(data).trim();
      commandHandler.handleCommand(commandLine, this);
    } catch (e, s) {
      logger.generalLog("error: $e stack: $s ,input bytes $data");
      sendResponse('500 Internal server error');
    }
  }

  void sendResponse(String message) {
    logger.logResponse(message);
    try {
      controlSocket.write('$message\r\n');
    } catch (e) {
      logger.generalLog('Error sending response: $e');
    }
  }

  void closeConnection() {
    controlSocket.close();
    dataSocket?.close();
    dataListener?.close();
    logger.generalLog('Connection closed');
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
    var result = dataListener!.first;
    if (timeout != null) {
      result = result.timeout(timeout, onTimeout: () {
        throw TimeoutException(
            'Timeout reached while waiting for client data socket');
      });
    }
    return result.then((value) => dataSocket = value);
  }

  Future<void> enterPassiveMode() async {
    try {
      dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      int port = dataListener!.port;
      int p1 = port >> 8;
      int p2 = port & 0xFF;
      var address = (await _getIpAddress()).replaceAll('.', ',');
      sendResponse('227 Entering Passive Mode ($address,$p1,$p2)');

      /// assigning the future to make sure it finishes before running any other operation
      /// check [openDataConnection]
      _gettingDataSocket =
          waitForClientDataSocket(timeout: Duration(seconds: 30));
    } catch (e) {
      sendResponse('425 Can\'t enter passive mode');
      logger.generalLog('Error entering passive mode: $e');
    }
  }

  Future<void> enterActiveMode(String parameters) async {
    try {
      List<String> parts = parameters.split(',');
      String ip = parts.take(4).join('.');
      int port = int.parse(parts[4]) * 256 + int.parse(parts[5]);
      dataSocket = await Socket.connect(ip, port);
      sendResponse('200 Active mode connection established');
    } catch (e) {
      sendResponse('425 Can\'t enter active mode');
      logger.generalLog('Error entering active mode: $e');
    }
  }

  Future<String> _getIpAddress() async {
    try {
      final networkInterfaces = await NetworkInterface.list();
      final ipList = networkInterfaces
          .map((interface) => interface.addresses)
          .expand((ip) => ip)
          .where((ip) => ip.type == InternetAddressType.IPv4)
          .toList();

      // Filter IPs that start with '192'
      final wifiIp = ipList.firstWhere(
        (address) => address.address.startsWith('192'),
        orElse: () => ipList.first,
      );

      return wifiIp.address;
    } catch (e) {
      logger.generalLog('Error getting IP address: $e');
    }
    return '0.0.0.0';
  }

  Future<void> listDirectory(String path) async {
    if (!await openDataConnection()) {
      return;
    }

    try {
      transferInProgress = true;

      var dirContents = await fileOperations.listDirectory(path);
      logger.generalLog(
          'Listing directory: $path, for ${fileOperations.resolvePath(path)} dir contents: $dirContents');

      for (FileSystemEntity entity in dirContents) {
        if (!transferInProgress) break; // Abort if transfer is cancelled

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
          // Continue with next entity
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

// Method to retrieve a file from the server
  Future<void> retrieveFile(String filename) async {
    if (!await openDataConnection()) {
      return;
    }

    try {
      transferInProgress = true;

      if (!fileOperations.exists(filename)) {
        sendResponse('550 File not found $filename');
        transferInProgress = false;
        await _closeDataSocket();
        return;
      }
      String fullPath = fileOperations.resolvePath(filename);

      File file = File(fullPath);
      if (await file.exists()) {
        Stream<List<int>> fileStream = file.openRead();

        // Handle potential socket errors during file transfer
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
      } else {
        sendResponse('550 File not found $fullPath');
        transferInProgress = false;
        await _closeDataSocket();
      }
    } catch (e) {
      logger.generalLog('Exception in retrieveFile: $e');
      sendResponse('550 File transfer failed');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

// Method to store a file on the server
  Future<void> storeFile(String filename) async {
    if (!await openDataConnection()) {
      return;
    }

    File? file;
    IOSink? fileSink;

    try {
      String fullPath = fileOperations.resolvePath(filename);
      transferInProgress = true;

      // Create the directory if it doesn't exist
      final directory = Directory(fullPath).parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      file = File(fullPath);
      fileSink = file.openWrite();

      // Handle socket errors during file upload
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
      sendResponse('550 Error creating file or directory: $e');
      transferInProgress = false;
      fileSink
          ?.close()
          .catchError((e) => logger.generalLog('Error closing file sink: $e'));
      await _closeDataSocket();
    }
  }

  // Helper method to handle transfer errors
  void _handleTransferError(IOSink? fileSink) async {
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

// Method to abort a file transfer
  void abortTransfer() async {
    if (transferInProgress) {
      transferInProgress = false;
      dataSocket?.destroy(); // Forcefully close the data socket
      sendResponse('426 Transfer aborted');
      dataSocket = null;
    } else {
      sendResponse('226 No transfer in progress');
    }
  }

  void changeDirectory(String dirname) {
    try {
      fileOperations.changeDirectory(dirname);
      sendResponse('250 Directory changed to $currentDirectory');
    } catch (e) {
      sendResponse('550 Access denied or directory not found $e');
      logger.generalLog('Error changing directory: $e');
    }
  }

  void changeToParentDirectory() {
    try {
      fileOperations.changeToParentDirectory();
      sendResponse('250 Directory changed to $currentDirectory');
    } catch (e) {
      sendResponse('550 Access denied or directory not found $e');
      logger.generalLog('Error changing to parent directory: $e');
    }
  }

  void makeDirectory(String dirname) async {
    try {
      await fileOperations.createDirectory(dirname);
      sendResponse('257 "$dirname" created');
    } catch (e) {
      sendResponse('550 Failed to create directory, error: $e');
      logger.generalLog('Error creating directory: $e');
    }
  }

  void removeDirectory(String dirname) async {
    try {
      await fileOperations.deleteDirectory(dirname);
      sendResponse('250 Directory deleted');
    } catch (e) {
      sendResponse('550 Failed to delete directory $e');
      logger.generalLog('Error deleting directory: $e');
    }
  }

  void deleteFile(String filePath) async {
    try {
      await fileOperations.deleteFile(filePath);
      sendResponse('250 File deleted');
    } catch (e) {
      sendResponse('550 Failed to delete file $e');
      logger.generalLog('Error deleting file: $e');
    }
  }

  Future<void> fileSize(String filePath) async {
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
      dataListener = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      int port = dataListener!.port;
      sendResponse('229 Entering Extended Passive Mode (|||$port|)');

      // Properly wait for the client to connect and handle errors
      _gettingDataSocket =
          waitForClientDataSocket(timeout: Duration(seconds: 30));
    } catch (e) {
      sendResponse('425 Can\'t enter extended passive mode');
      logger.generalLog('Error entering extended passive mode: $e');
    }
  }

  Future<void> handleMlsd(String argument, FtpSession session) async {
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
          // Continue with next entity
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
      sendResponse('550 Failed to list directory: $e');
      transferInProgress = false;
      await _closeDataSocket();
    }
  }

// Method to abort a file transfer
  String _formatMlsdFacts(FileSystemEntity entity, FileStat stat) {
    String type = stat.type == FileSystemEntityType.directory ? "dir" : "file";
    String modify = DateFormat("yyyyMMddHHmmss")
        .format(stat.modified.toUtc()); // Use UTC time
    String size = stat.size.toString();
    String name = entity.path.split(Platform.pathSeparator).last;

    return "type=$type;modify=$modify;size=$size; $name\r\n";
  }

  void handleMdtm(String argument, FtpSession session) {
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
      sendResponse('550 Could not get modification time: $e');
      logger.generalLog('Error getting modification time: $e');
    }
  }

  String _formatMdtmTimestamp(DateTime dateTime) {
    return DateFormat('yyyyMMddHHmmss').format(dateTime.toUtc()); // Use UTC
  }
}
