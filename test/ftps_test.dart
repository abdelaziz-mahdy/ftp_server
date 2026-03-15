// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:test/test.dart';

/// Wraps a socket stream to allow reading multiple responses sequentially.
/// Dart sockets are single-subscription streams, so we need to subscribe once
/// and buffer the data.
class FtpConnection {
  dynamic _socket;
  final _buffer = StringBuffer();
  final _dataController = StreamController<void>.broadcast();
  StreamSubscription? _subscription;
  bool _closed = false;

  FtpConnection(this._socket) {
    _startListening();
  }

  void _startListening() {
    _subscription = _socket.listen(
      (List<int> data) {
        _buffer.write(utf8.decode(data));
        _dataController.add(null);
      },
      onError: (e) {
        if (!_closed) {
          _dataController.addError(e);
        }
      },
      onDone: () {
        _closed = true;
        _dataController.close();
      },
    );
  }

  /// Read a single FTP response line (ending with \r\n, starting with 3-digit code).
  Future<String> readResponse({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? const Duration(seconds: 5);
    final deadline = DateTime.now().add(effectiveTimeout);

    while (true) {
      final content = _buffer.toString();
      // Look for a complete response line (NNN followed by space or dash, then \r\n)
      final lines = content.split('\r\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.isNotEmpty && RegExp(r'^\d{3}[ ]').hasMatch(line)) {
          // Found a complete single response line - consume up to and including this line
          final consumed =
              '${lines.sublist(0, i + 1).join('\r\n')}\r\n';
          final remaining = content.substring(consumed.length);
          _buffer.clear();
          _buffer.write(remaining);
          return line.trim();
        }
      }

      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
            'Timeout reading response. Buffer: ${_buffer.toString()}');
      }

      // Wait for more data
      await _dataController.stream.first.timeout(
        deadline.difference(DateTime.now()),
        onTimeout: () {
          throw TimeoutException(
              'Timeout reading response. Buffer: ${_buffer.toString()}');
        },
      );
    }
  }

  /// Read a multi-line FTP response (e.g., FEAT response: 211-Features:\r\n...\r\n211 End\r\n).
  Future<String> readMultiLineResponse({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? const Duration(seconds: 5);
    final deadline = DateTime.now().add(effectiveTimeout);

    while (true) {
      final content = _buffer.toString();
      // Multi-line response ends when we find "NNN " (with space, not dash) at start of line
      // after an initial "NNN-" line
      final lines = content.split('\r\n');
      bool foundStart = false;
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!foundStart && RegExp(r'^\d{3}-').hasMatch(line)) {
          foundStart = true;
        }
        if (foundStart && RegExp(r'^\d{3} ').hasMatch(line)) {
          // Found the end - consume everything up to and including this line
          final consumed =
              '${lines.sublist(0, i + 1).join('\r\n')}\r\n';
          final remaining = content.substring(consumed.length);
          _buffer.clear();
          _buffer.write(remaining);
          return lines.sublist(0, i + 1).join('\r\n').trim();
        }
      }

      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
            'Timeout reading multi-line response. Buffer: ${_buffer.toString()}');
      }

      await _dataController.stream.first.timeout(
        deadline.difference(DateTime.now()),
        onTimeout: () {
          throw TimeoutException(
              'Timeout reading multi-line response. Buffer: ${_buffer.toString()}');
        },
      );
    }
  }

  void sendCommand(String command) {
    _socket.write('$command\r\n');
  }

  /// Replace the underlying socket (used during TLS upgrade).
  /// Pauses the old subscription (don't cancel - SecureSocket.secure needs it
  /// for _detachRaw), upgrades to TLS, then re-subscribes on the new socket.
  Future<void> upgradeToSecure({bool Function(X509Certificate)? onBadCertificate}) async {
    // Pause, don't cancel. SecureSocket.secure() internally detaches the raw
    // socket and takes ownership of the subscription via _detachRaw().
    _subscription?.pause();
    _socket = await SecureSocket.secure(
      _socket as Socket,
      onBadCertificate: onBadCertificate ?? (_) => true,
    );
    // Ownership transferred to SecureSocket
    _subscription = null;
    _startListening();
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _socket.close();
  }
}

void main() {
  group('Explicit FTPS (AUTH TLS)', () {
    late FtpServer server;
    late Directory tempDir;
    const int port = 2200;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('ftps_test_');
      // Create a test file
      File('${tempDir.path}/test.txt').writeAsStringSync('Hello FTPS!');

      final dirName = tempDir.path.split(Platform.pathSeparator).last;
      server = FtpServer(
        port,
        username: 'test',
        password: 'password',
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: dirName),
        serverType: ServerType.readAndWrite,
        logFunction: (msg) => print('[FTPS Server] $msg'),
        secureConnectionAllowed: true,
        secureDataConnection: true,
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    test('Server accepts plain connection and responds with 220', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      final welcome = await conn.readResponse();
      expect(welcome, startsWith('220'));
      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('FEAT lists AUTH TLS, PBSZ, PROT', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220 welcome

      conn.sendCommand('FEAT');
      final featResponse = await conn.readMultiLineResponse();
      expect(featResponse, contains('AUTH TLS'));
      expect(featResponse, contains('PBSZ'));
      expect(featResponse, contains('PROT'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('AUTH TLS upgrades connection to TLS successfully', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220 welcome

      conn.sendCommand('AUTH TLS');
      final authResponse = await conn.readResponse();
      expect(authResponse, startsWith('234'));

      // Upgrade to TLS
      await conn.upgradeToSecure();

      // After TLS upgrade, commands should still work
      conn.sendCommand('USER test');
      final userResponse = await conn.readResponse();
      expect(userResponse, startsWith('331'));

      conn.sendCommand('PASS password');
      final passResponse = await conn.readResponse();
      expect(passResponse, startsWith('230'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('Commands work after AUTH TLS upgrade', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220 welcome

      conn.sendCommand('AUTH TLS');
      await conn.readResponse(); // 234

      await conn.upgradeToSecure();

      // Authenticate
      conn.sendCommand('USER test');
      await conn.readResponse(); // 331

      conn.sendCommand('PASS password');
      await conn.readResponse(); // 230

      // PWD
      conn.sendCommand('PWD');
      final pwdResponse = await conn.readResponse();
      expect(pwdResponse, startsWith('257'));

      // SYST
      conn.sendCommand('SYST');
      final systResponse = await conn.readResponse();
      expect(systResponse, startsWith('215'));

      // TYPE
      conn.sendCommand('TYPE I');
      final typeResponse = await conn.readResponse();
      expect(typeResponse, startsWith('200'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('PBSZ 0 works after AUTH TLS', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('AUTH TLS');
      await conn.readResponse(); // 234

      await conn.upgradeToSecure();

      conn.sendCommand('PBSZ 0');
      final pbszResponse = await conn.readResponse();
      expect(pbszResponse, startsWith('200'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('PROT P and PROT C work after AUTH TLS', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('AUTH TLS');
      await conn.readResponse(); // 234

      await conn.upgradeToSecure();

      conn.sendCommand('PBSZ 0');
      await conn.readResponse(); // 200

      conn.sendCommand('PROT P');
      final protPResponse = await conn.readResponse();
      expect(protPResponse, startsWith('200'));
      expect(protPResponse, contains('Private'));

      conn.sendCommand('PROT C');
      final protCResponse = await conn.readResponse();
      expect(protCResponse, startsWith('200'));
      expect(protCResponse, contains('Clear'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('PBSZ fails before AUTH TLS', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('PBSZ 0');
      final pbszResponse = await conn.readResponse();
      expect(pbszResponse, startsWith('503'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('PROT fails before AUTH TLS', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('PROT P');
      final protResponse = await conn.readResponse();
      expect(protResponse, startsWith('503'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('AUTH TLS rejected when already secure', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('AUTH TLS');
      await conn.readResponse(); // 234

      await conn.upgradeToSecure();

      // Try AUTH TLS again - should fail
      conn.sendCommand('AUTH TLS');
      final response = await conn.readResponse();
      expect(response, startsWith('503'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('Invalid AUTH type returns 504', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('AUTH SSL');
      final response = await conn.readResponse();
      expect(response, startsWith('504'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('Invalid PBSZ argument returns 501', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('AUTH TLS');
      await conn.readResponse(); // 234

      await conn.upgradeToSecure();

      conn.sendCommand('PBSZ 1024');
      final response = await conn.readResponse();
      expect(response, startsWith('501'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('Invalid PROT level returns 504', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('AUTH TLS');
      await conn.readResponse(); // 234

      await conn.upgradeToSecure();

      conn.sendCommand('PROT S');
      final response = await conn.readResponse();
      expect(response, startsWith('504'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('Full FTPS session with directory listing over TLS data channel',
        () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      // AUTH TLS
      conn.sendCommand('AUTH TLS');
      await conn.readResponse(); // 234
      await conn.upgradeToSecure();

      // PBSZ + PROT P
      conn.sendCommand('PBSZ 0');
      await conn.readResponse(); // 200

      conn.sendCommand('PROT P');
      await conn.readResponse(); // 200

      // Authenticate
      conn.sendCommand('USER test');
      await conn.readResponse(); // 331

      conn.sendCommand('PASS password');
      await conn.readResponse(); // 230

      // EPSV
      conn.sendCommand('EPSV');
      final epsvResponse = await conn.readResponse();
      expect(epsvResponse, startsWith('229'));

      // Extract port from EPSV response
      final portMatch = RegExp(r'\|\|\|(\d+)\|').firstMatch(epsvResponse);
      expect(portMatch, isNotNull);
      final dataPort = int.parse(portMatch!.group(1)!);

      // Connect data socket (plain first, server upgrades after 150)
      final dataSocket = await Socket.connect('127.0.0.1', dataPort);

      // LIST
      conn.sendCommand('LIST');
      final listResponse = await conn.readResponse();
      expect(listResponse, startsWith('150'));

      // Server upgrades data channel to TLS after 150, so we upgrade our side
      final secureDataSocket = await SecureSocket.secure(
        dataSocket,
        onBadCertificate: (_) => true,
      );

      // Read the directory listing data
      final dataCompleter = Completer<String>();
      final dataBuffer = StringBuffer();
      secureDataSocket.listen(
        (data) => dataBuffer.write(utf8.decode(data)),
        onDone: () {
          if (!dataCompleter.isCompleted) {
            dataCompleter.complete(dataBuffer.toString());
          }
        },
        onError: (e) {
          if (!dataCompleter.isCompleted) {
            dataCompleter.completeError(e);
          }
        },
      );

      final listData =
          await dataCompleter.future.timeout(const Duration(seconds: 10));
      expect(listData, contains('test.txt'));

      // Read 226 Transfer complete
      final transferComplete = await conn.readResponse();
      expect(transferComplete, startsWith('226'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('PROT C disables data channel TLS', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('AUTH TLS');
      await conn.readResponse(); // 234
      await conn.upgradeToSecure();

      conn.sendCommand('PBSZ 0');
      await conn.readResponse(); // 200

      // Set PROT C (clear data channel)
      conn.sendCommand('PROT C');
      final protResponse = await conn.readResponse();
      expect(protResponse, startsWith('200'));

      // Authenticate
      conn.sendCommand('USER test');
      await conn.readResponse(); // 331
      conn.sendCommand('PASS password');
      await conn.readResponse(); // 230

      // EPSV
      conn.sendCommand('EPSV');
      final epsvResponse = await conn.readResponse();
      final portMatch = RegExp(r'\|\|\|(\d+)\|').firstMatch(epsvResponse);
      final dataPort = int.parse(portMatch!.group(1)!);

      // Connect data socket (plain - since PROT C)
      final dataSocket = await Socket.connect('127.0.0.1', dataPort);

      // LIST
      conn.sendCommand('LIST');
      final listResponse = await conn.readResponse();
      expect(listResponse, startsWith('150'));

      // Read listing data in plain (no TLS upgrade needed)
      final dataCompleter = Completer<String>();
      final dataBuffer = StringBuffer();
      dataSocket.listen(
        (data) => dataBuffer.write(utf8.decode(data)),
        onDone: () {
          if (!dataCompleter.isCompleted) {
            dataCompleter.complete(dataBuffer.toString());
          }
        },
        onError: (e) {
          if (!dataCompleter.isCompleted) {
            dataCompleter.completeError(e);
          }
        },
      );

      final listData =
          await dataCompleter.future.timeout(const Duration(seconds: 10));
      expect(listData, contains('test.txt'));

      final transferComplete = await conn.readResponse();
      expect(transferComplete, startsWith('226'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('File retrieval works over TLS data channel', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      // AUTH TLS
      conn.sendCommand('AUTH TLS');
      await conn.readResponse(); // 234
      await conn.upgradeToSecure();

      // PBSZ + PROT P
      conn.sendCommand('PBSZ 0');
      await conn.readResponse(); // 200
      conn.sendCommand('PROT P');
      await conn.readResponse(); // 200

      // Authenticate
      conn.sendCommand('USER test');
      await conn.readResponse(); // 331
      conn.sendCommand('PASS password');
      await conn.readResponse(); // 230

      // EPSV for data connection
      conn.sendCommand('EPSV');
      final epsvResponse = await conn.readResponse();
      final portMatch = RegExp(r'\|\|\|(\d+)\|').firstMatch(epsvResponse);
      final dataPort = int.parse(portMatch!.group(1)!);

      final dataSocket = await Socket.connect('127.0.0.1', dataPort);

      // RETR
      conn.sendCommand('RETR test.txt');
      final retrResponse = await conn.readResponse();
      expect(retrResponse, startsWith('150'));

      // Upgrade data channel to TLS
      final secureDataSocket = await SecureSocket.secure(
        dataSocket,
        onBadCertificate: (_) => true,
      );

      // Read file data
      final dataCompleter = Completer<String>();
      final dataBuffer = StringBuffer();
      secureDataSocket.listen(
        (data) => dataBuffer.write(utf8.decode(data)),
        onDone: () {
          if (!dataCompleter.isCompleted) {
            dataCompleter.complete(dataBuffer.toString());
          }
        },
        onError: (e) {
          if (!dataCompleter.isCompleted) {
            dataCompleter.completeError(e);
          }
        },
      );

      final fileData =
          await dataCompleter.future.timeout(const Duration(seconds: 10));
      expect(fileData, equals('Hello FTPS!'));

      final transferComplete = await conn.readResponse();
      expect(transferComplete, startsWith('226'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });
  });

  group('FTPS disabled server', () {
    late FtpServer server;
    late Directory tempDir;
    const int port = 2201;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('ftps_disabled_test_');

      server = FtpServer(
        port,
        fileOperations: VirtualFileOperations([tempDir.path]),
        serverType: ServerType.readOnly,
        logFunction: (msg) => print('[No-FTPS Server] $msg'),
        // No FTPS settings - all default to false
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    test('AUTH TLS rejected when not enabled', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('AUTH TLS');
      final response = await conn.readResponse();
      expect(response, startsWith('502'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('FEAT does not list AUTH TLS when not enabled', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final conn = FtpConnection(socket);
      await conn.readResponse(); // 220

      conn.sendCommand('FEAT');
      final featResponse = await conn.readMultiLineResponse();
      expect(featResponse, isNot(contains('AUTH TLS')));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });
  });

  group('Implicit FTPS', () {
    late FtpServer server;
    late Directory tempDir;
    const int port = 2202;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('ftps_implicit_test_');
      File('${tempDir.path}/secure.txt').writeAsStringSync('Secure content');

      server = FtpServer(
        port,
        username: 'test',
        password: 'password',
        fileOperations: VirtualFileOperations([tempDir.path]),
        serverType: ServerType.readAndWrite,
        logFunction: (msg) => print('[Implicit FTPS] $msg'),
        enforceSecureConnections: true,
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    test('Implicit FTPS accepts TLS connection directly', () async {
      final secureSocket = await SecureSocket.connect(
        '127.0.0.1',
        port,
        onBadCertificate: (_) => true,
      );
      final conn = FtpConnection(secureSocket);

      final welcome = await conn.readResponse();
      expect(welcome, startsWith('220'));

      conn.sendCommand('USER test');
      final userResponse = await conn.readResponse();
      expect(userResponse, startsWith('331'));

      conn.sendCommand('PASS password');
      final passResponse = await conn.readResponse();
      expect(passResponse, startsWith('230'));

      conn.sendCommand('PWD');
      final pwdResponse = await conn.readResponse();
      expect(pwdResponse, startsWith('257'));

      conn.sendCommand('QUIT');
      await conn.readResponse();
      await conn.close();
    });

    test('Implicit FTPS rejects plain connection', () async {
      // A plain socket connecting to an implicit FTPS port should fail
      // because the server expects TLS from the start
      try {
        final socket = await Socket.connect('127.0.0.1', port);
        final conn = FtpConnection(socket);
        // Try to read - we should get garbage or timeout since
        // the server is speaking TLS
        final response =
            await conn.readResponse(timeout: Duration(seconds: 2));
        // If we get here, the response should not be a valid FTP response
        expect(response, isNot(startsWith('220')));
        await conn.close();
      } on TimeoutException {
        // Expected - TLS handshake bytes don't form a valid FTP response
      } on SocketException {
        // Also acceptable - connection may be refused
      }
    });
  });
}
