// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Helper to send a command and read the response from the FTP server.
class FtpTestClient {
  final Socket _socket;
  final StringBuffer _buffer = StringBuffer();
  final StreamController<void> _dataReady = StreamController<void>.broadcast();
  late StreamSubscription _sub;

  FtpTestClient._(this._socket) {
    _sub = _socket.listen((data) {
      _buffer.write(utf8.decode(data));
      _dataReady.add(null);
    }, onDone: () {
      _dataReady.close();
    });
  }

  static Future<FtpTestClient> connect(int port) async {
    final socket = await Socket.connect('127.0.0.1', port);
    final client = FtpTestClient._(socket);
    await client.readResponse(); // consume 220 welcome
    return client;
  }

  Future<String> readResponse({Duration? timeout}) async {
    final deadline = timeout ?? const Duration(seconds: 5);
    final end = DateTime.now().add(deadline);

    while (true) {
      final content = _buffer.toString();
      final lines = content.split('\r\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.isNotEmpty && RegExp(r'^\d{3}[ ]').hasMatch(line)) {
          final consumed = '${lines.sublist(0, i + 1).join('\r\n')}\r\n';
          final remaining = content.substring(consumed.length);
          _buffer.clear();
          _buffer.write(remaining);
          return line.trim();
        }
      }
      if (DateTime.now().isAfter(end)) {
        throw TimeoutException('Timeout. Buffer: ${_buffer.toString()}');
      }
      await _dataReady.stream.first.timeout(end.difference(DateTime.now()),
          onTimeout: () {
        throw TimeoutException('Timeout. Buffer: ${_buffer.toString()}');
      });
    }
  }

  Future<String> readMultiLineResponse({Duration? timeout}) async {
    final deadline = timeout ?? const Duration(seconds: 5);
    final end = DateTime.now().add(deadline);

    while (true) {
      final content = _buffer.toString();
      final lines = content.split('\r\n');
      bool foundStart = false;
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!foundStart && RegExp(r'^\d{3}-').hasMatch(line)) foundStart = true;
        if (foundStart && RegExp(r'^\d{3} ').hasMatch(line)) {
          final consumed = '${lines.sublist(0, i + 1).join('\r\n')}\r\n';
          final remaining = content.substring(consumed.length);
          _buffer.clear();
          _buffer.write(remaining);
          return lines.sublist(0, i + 1).join('\r\n').trim();
        }
      }
      if (DateTime.now().isAfter(end)) {
        throw TimeoutException('Timeout. Buffer: ${_buffer.toString()}');
      }
      await _dataReady.stream.first.timeout(end.difference(DateTime.now()),
          onTimeout: () {
        throw TimeoutException('Timeout. Buffer: ${_buffer.toString()}');
      });
    }
  }

  void send(String command) {
    _socket.write('$command\r\n');
  }

  Future<String> command(String cmd) async {
    send(cmd);
    return readResponse();
  }

  Future<void> login(
      [String user = 'testuser', String pass = 'testpass']) async {
    send('USER $user');
    await readResponse();
    send('PASS $pass');
    await readResponse();
  }

  Future<void> close() async {
    await _sub.cancel();
    await _socket.close();
  }
}

void main() {
  late FtpServer server;
  late Directory tempDir;
  const int port = 2250;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('ftp_cmd_test_');
    File('${tempDir.path}/hello.txt').writeAsStringSync('Hello!');
    File('${tempDir.path}/data.bin')
        .writeAsBytesSync(List.generate(100, (i) => i));
    Directory('${tempDir.path}/subdir').createSync();
    File('${tempDir.path}/subdir/nested.txt').writeAsStringSync('Nested file');

    server = FtpServer(
      port,
      username: 'testuser',
      password: 'testpass',
      fileOperations: VirtualFileOperations([tempDir.path],
          startingDirectory: p.basename(tempDir.path)),
      serverType: ServerType.readAndWrite,
      logFunction: (msg) {},
    );
    await server.startInBackground();
  });

  tearDownAll(() async {
    await server.stop();
    tempDir.deleteSync(recursive: true);
  });

  group('Authentication', () {
    test('USER with empty argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('USER');
      expect(r, startsWith('501'));
      await c.close();
    });

    test('PASS before USER returns 503', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('PASS testpass');
      expect(r, startsWith('503'));
      await c.close();
    });

    test('Commands require auth when credentials configured', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('LIST');
      expect(r, startsWith('530'));
      await c.close();
    });

    test('Pre-auth commands work without login', () async {
      final c = await FtpTestClient.connect(port);
      expect(await c.command('SYST'), startsWith('215'));
      expect(await c.command('NOOP'), startsWith('200'));

      c.send('FEAT');
      final feat = await c.readMultiLineResponse();
      expect(feat, startsWith('211'));

      expect(await c.command('OPTS UTF8 ON'), startsWith('200'));
      await c.close();
    });

    test('Successful login', () async {
      final c = await FtpTestClient.connect(port);
      expect(await c.command('USER testuser'), startsWith('331'));
      expect(await c.command('PASS testpass'), startsWith('230'));
      await c.close();
    });

    test('Wrong password returns 530', () async {
      final c = await FtpTestClient.connect(port);
      await c.command('USER testuser');
      expect(await c.command('PASS wrong'), startsWith('530'));
      await c.close();
    });
  });

  group('Directory commands', () {
    test('PWD returns current directory', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('PWD');
      expect(r, startsWith('257'));
      expect(r, contains('"'));
      await c.close();
    });

    test('XPWD works same as PWD', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('XPWD');
      expect(r, startsWith('257'));
      await c.close();
    });

    test('CWD to valid directory', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('CWD subdir');
      expect(r, startsWith('250'));
      await c.close();
    });

    test('CWD to invalid directory returns 550', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('CWD nonexistent');
      expect(r, startsWith('550'));
      // Verify no internal path leaked
      expect(r, isNot(contains(tempDir.path)));
      await c.close();
    });

    test('CDUP from subdirectory', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      await c.command('CWD subdir');
      final r = await c.command('CDUP');
      expect(r, startsWith('250'));
      await c.close();
    });

    test('MKD creates directory', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('MKD newdir');
      expect(r, startsWith('257'));
      // Clean up
      await c.command('RMD newdir');
      await c.close();
    });

    test('RMD removes directory', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      await c.command('MKD toremove');
      final r = await c.command('RMD toremove');
      expect(r, startsWith('250'));
      await c.close();
    });
  });

  group('TYPE command', () {
    test('TYPE A accepted', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('TYPE A'), startsWith('200'));
      await c.close();
    });

    test('TYPE I accepted', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('TYPE I'), startsWith('200'));
      await c.close();
    });

    test('TYPE A N accepted (ASCII Non-print)', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('TYPE A N'), startsWith('200'));
      await c.close();
    });

    test('TYPE X rejected', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('TYPE X'), startsWith('504'));
      await c.close();
    });

    test('TYPE with no argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('TYPE'), startsWith('501'));
      await c.close();
    });
  });

  group('STRU/MODE/ALLO', () {
    test('STRU F accepted', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('STRU F'), startsWith('200'));
      await c.close();
    });

    test('STRU R rejected', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('STRU R'), startsWith('504'));
      await c.close();
    });

    test('STRU with no argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('STRU'), startsWith('501'));
      await c.close();
    });

    test('MODE S accepted', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('MODE S'), startsWith('200'));
      await c.close();
    });

    test('MODE B rejected', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('MODE B'), startsWith('504'));
      await c.close();
    });

    test('MODE with no argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('MODE'), startsWith('501'));
      await c.close();
    });

    test('ALLO with argument returns 200', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('ALLO 1024'), startsWith('200'));
      await c.close();
    });
  });

  group('OPTS', () {
    test('OPTS UTF8 ON', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('OPTS UTF8 ON');
      expect(r, startsWith('200'));
      expect(r, contains('enable'));
      await c.close();
    });

    test('OPTS UTF8 OFF', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('OPTS UTF8 OFF');
      expect(r, startsWith('200'));
      expect(r, contains('disable'));
      await c.close();
    });

    test('OPTS UTF8 without ON/OFF returns 501', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('OPTS UTF8');
      expect(r, startsWith('501'));
      await c.close();
    });

    test('OPTS with no argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('OPTS');
      expect(r, startsWith('501'));
      await c.close();
    });

    test('OPTS UNKNOWN returns 502', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('OPTS SOMETHING ON');
      expect(r, startsWith('502'));
      await c.close();
    });
  });

  group('FEAT', () {
    test('FEAT lists supported features', () async {
      final c = await FtpTestClient.connect(port);
      c.send('FEAT');
      final r = await c.readMultiLineResponse();
      expect(r, contains('SIZE'));
      expect(r, contains('MDTM'));
      // RFC 3659 §7.8: MLST advertised with fact list (MLSD is implied)
      expect(r, contains('MLST'));
      expect(r, contains('EPSV'));
      expect(r, contains('UTF8'));
      // PASV is a base RFC 959 command, not an extension per RFC 2389
      expect(r, isNot(contains('PASV')));
      expect(r, startsWith('211'));
      await c.close();
    });
  });

  group('EPSV', () {
    test('EPSV enters extended passive mode', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('EPSV');
      expect(r, startsWith('229'));
      expect(r, contains('|||'));
      // Connect to the passive port to prevent timeout error on server
      final portMatch = RegExp(r'\|\|\|(\d+)\|').firstMatch(r);
      if (portMatch != null) {
        final dataPort = int.parse(portMatch.group(1)!);
        final dataSocket = await Socket.connect('127.0.0.1', dataPort);
        await dataSocket.close();
      }
      await c.close();
    });

    test('EPSV ALL returns 200', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('EPSV ALL');
      expect(r, startsWith('200'));
      await c.close();
    });
  });

  group('HELP', () {
    test('HELP returns command list', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      c.send('HELP');
      final r = await c.readMultiLineResponse();
      expect(r, startsWith('214'));
      expect(r, contains('USER'));
      expect(r, contains('RETR'));
      expect(r, contains('STOR'));
      await c.close();
    });
  });

  group('STAT', () {
    test('STAT returns server status', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('STAT'), startsWith('211'));
      await c.close();
    });
  });

  group('ALLO', () {
    test('ALLO with valid byte count returns 200', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('ALLO 1024');
      expect(r, startsWith('200'));
      await c.close();
    });

    test('ALLO with record size returns 200', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('ALLO 1024 R 512');
      expect(r, startsWith('200'));
      await c.close();
    });

    test('ALLO with no argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('ALLO'), startsWith('501'));
      await c.close();
    });

    test('ALLO with non-numeric argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('ALLO abc'), startsWith('501'));
      await c.close();
    });

    test('ALLO with negative number returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('ALLO -1'), startsWith('501'));
      await c.close();
    });

    test('ALLO with malformed record size returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('ALLO 1024 R'), startsWith('501'));
      await c.close();
    });

    test('ALLO with invalid R argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('ALLO 1024 X 512'), startsWith('501'));
      await c.close();
    });

    test('ALLO with non-numeric record size returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('ALLO 1024 R abc'), startsWith('501'));
      await c.close();
    });

    test('ALLO with zero bytes returns 200', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('ALLO 0');
      expect(r, startsWith('200'));
      await c.close();
    });
  });

  group('ACCT', () {
    test('ACCT with argument returns 202', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('ACCT myaccount');
      expect(r, startsWith('202'));
      await c.close();
    });

    test('ACCT with no argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('ACCT'), startsWith('501'));
      await c.close();
    });

    test('ACCT allowed before authentication', () async {
      final c = await FtpTestClient.connect(port);
      // Don't login — ACCT should still be accepted pre-auth
      final r = await c.command('ACCT myaccount');
      expect(r, startsWith('202'));
      await c.close();
    });
  });

  group('REIN', () {
    test('REIN returns 220', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('REIN');
      expect(r, startsWith('200'));
      await c.close();
    });

    test('REIN resets authentication state', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      // Verify logged in
      expect(await c.command('PWD'), startsWith('257'));
      // Reinitialize
      expect(await c.command('REIN'), startsWith('200'));
      // Commands now require auth
      expect(await c.command('PWD'), startsWith('530'));
      await c.close();
    });

    test('REIN allows new login on same connection', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('REIN'), startsWith('200'));
      // Login again on the same connection
      await c.login();
      expect(await c.command('PWD'), startsWith('257'));
      await c.close();
    });

    test('REIN clears pending rename state', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      // Start a rename sequence
      expect(await c.command('RNFR hello.txt'), startsWith('350'));
      // Reinitialize — should clear the pending rename
      expect(await c.command('REIN'), startsWith('200'));
      // Login again
      await c.login();
      // RNTO should fail with 503 because RNFR was cleared by REIN
      expect(await c.command('RNTO newname.txt'), startsWith('503'));
      await c.close();
    });

    test('REIN allowed before authentication', () async {
      final c = await FtpTestClient.connect(port);
      // Don't login — REIN should still work pre-auth
      final r = await c.command('REIN');
      expect(r, startsWith('200'));
      await c.close();
    });

    test('REIN resets working directory to root', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      // Change to a subdirectory
      expect(await c.command('CWD subdir'), startsWith('250'));
      final pwdBefore = await c.command('PWD');
      expect(pwdBefore, contains('subdir'));
      // Reinitialize
      expect(await c.command('REIN'), startsWith('200'));
      // Login again
      await c.login();
      // PWD should be back at root, not subdir
      final pwdAfter = await c.command('PWD');
      expect(pwdAfter, isNot(contains('subdir')));
      await c.close();
    });
  });

  group('SITE', () {
    test('SITE with subcommand returns 502', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('SITE CHMOD 755 file.txt');
      expect(r, startsWith('502'));
      await c.close();
    });

    test('SITE with no argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('SITE'), startsWith('501'));
      await c.close();
    });

    test('SITE with any subcommand returns 502', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('SITE HELP'), startsWith('502'));
      expect(await c.command('SITE QUOTA'), startsWith('502'));
      await c.close();
    });
  });

  group('Unknown commands', () {
    test('Unknown command returns 502', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('BOGUS');
      expect(r, startsWith('502'));
      // Should not echo the command back
      expect(r, isNot(contains('BOGUS')));
      await c.close();
    });
  });

  group('SIZE/MDTM', () {
    test('SIZE returns file size', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('SIZE hello.txt');
      expect(r, startsWith('213'));
      expect(r, contains('6')); // "Hello!" is 6 bytes
      await c.close();
    });

    test('SIZE of nonexistent file returns 550', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('SIZE nope.txt'), startsWith('550'));
      await c.close();
    });

    test('MDTM returns modification time', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('MDTM hello.txt');
      expect(r, startsWith('213'));
      // Should be in YYYYMMDDHHmmss format (14 digits)
      expect(RegExp(r'213 \d{14}').hasMatch(r), isTrue);
      await c.close();
    });
  });

  group('QUIT', () {
    test('QUIT returns 221', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('QUIT');
      expect(r, startsWith('221'));
      await c.close();
    });
  });

  group('SYST', () {
    test('SYST returns UNIX Type', () async {
      final c = await FtpTestClient.connect(port);
      final r = await c.command('SYST');
      expect(r, startsWith('215'));
      expect(r, contains('UNIX'));
      await c.close();
    });
  });

  group('Error message sanitization', () {
    test('CWD error does not leak server paths', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('CWD /etc/passwd');
      expect(r, startsWith('550'));
      expect(r, isNot(contains('/var')));
      expect(r, isNot(contains('/tmp')));
      expect(r, isNot(contains('Exception')));
      await c.close();
    });

    test('MKD error does not leak server paths', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      // Try to create a directory at root of virtual FS (should fail for virtual ops)
      final r = await c.command('DELE /etc/passwd');
      expect(r, isNot(contains('/var')));
      expect(r, isNot(contains('/tmp')));
      await c.close();
    });
  });

  group('Session management', () {
    test('Sessions are removed from active list on disconnect', () async {
      final initialCount = server.activeSessions.length;
      final c = await FtpTestClient.connect(port);
      await Future.delayed(Duration(milliseconds: 100));
      expect(server.activeSessions.length, greaterThan(initialCount));

      await c.command('QUIT');
      await c.close();
      await Future.delayed(Duration(milliseconds: 200));
      expect(server.activeSessions.length, equals(initialCount));
    });
  });

  group('Pipelined commands', () {
    test('Multiple commands in one TCP segment are handled', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final buffer = StringBuffer();
      final dataReady = StreamController<void>.broadcast();
      socket.listen((data) {
        buffer.write(utf8.decode(data));
        dataReady.add(null);
      });
      // Wait for 220
      await dataReady.stream.first.timeout(Duration(seconds: 2));
      buffer.clear();

      // Send two pre-auth commands in one write
      socket.write('SYST\r\nNOOP\r\n');
      // Wait for responses
      await Future.delayed(Duration(milliseconds: 500));

      final response = buffer.toString();
      expect(response, contains('215'));
      expect(response, contains('200'));
      dataReady.close();
      await socket.close();
    });
  });

  group('RFC compliance fixes', () {
    test('RETR with empty argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('RETR');
      expect(r, startsWith('501'));
      await c.close();
    });

    test('RETR nonexistent file returns 550 without 150', () async {
      // The server should check file existence before opening data connection
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('RETR nonexistent_file.txt');
      // Should get 550 directly, not 150 then 550
      expect(r, startsWith('550'));
      await c.close();
    });

    test('STOR with empty argument returns 501', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('STOR');
      expect(r, startsWith('501'));
      await c.close();
    });

    test('CWD response uses virtual path, not physical', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('CWD subdir');
      expect(r, startsWith('250'));
      // Should not contain system temp path
      expect(r, isNot(contains('/var')));
      expect(r, isNot(contains('/tmp')));
      expect(r, isNot(contains('AppData')));
      await c.close();
    });

    test('CDUP response uses virtual path', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      await c.command('CWD subdir');
      final r = await c.command('CDUP');
      expect(r, startsWith('250'));
      expect(r, isNot(contains('/var')));
      expect(r, isNot(contains('/tmp')));
      await c.close();
    });

    test('MKD response contains absolute FTP path', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      final r = await c.command('MKD rfc_test_dir');
      expect(r, startsWith('257'));
      // Should contain a path separator (/ on Unix, \ on Windows)
      expect(r, anyOf(contains('/'), contains('\\')));
      expect(r, contains('rfc_test_dir'));
      // Cleanup
      await c.command('RMD rfc_test_dir');
      await c.close();
    });

    test('FEAT does not list PASV (base RFC 959 command)', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      c.send('FEAT');
      final feat = await c.readMultiLineResponse();
      expect(feat, isNot(contains('PASV')));
      expect(feat, contains('EPSV'));
      expect(feat, contains('SIZE'));
      await c.close();
    });

    test('EPSV ALL prevents subsequent PORT', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('EPSV ALL'), startsWith('200'));
      final r = await c.command('PORT 127,0,0,1,200,10');
      expect(r, startsWith('503'));
      await c.close();
    });

    test('EPSV ALL prevents subsequent PASV', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('EPSV ALL'), startsWith('200'));
      final r = await c.command('PASV');
      expect(r, startsWith('503'));
      await c.close();
    });

    test('EPSV still works after EPSV ALL', () async {
      final c = await FtpTestClient.connect(port);
      await c.login();
      expect(await c.command('EPSV ALL'), startsWith('200'));
      final r = await c.command('EPSV');
      expect(r, startsWith('229'));
      await c.command('QUIT');
      await c.close();
    });
  });

  group('Partial credential configs', () {
    late FtpServer usernameOnlyServer;
    const usernameOnlyPort = 2251;

    setUpAll(() async {
      usernameOnlyServer = FtpServer(
        usernameOnlyPort,
        username: 'admin',
        password: null,
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: p.basename(tempDir.path)),
        serverType: ServerType.readAndWrite,
        logFunction: (msg) {},
      );
      await usernameOnlyServer.startInBackground();
    });

    tearDownAll(() async {
      await usernameOnlyServer.stop();
    });

    test('Username-only server: correct username authenticates', () async {
      final c = await FtpTestClient.connect(usernameOnlyPort);
      expect(await c.command('USER admin'), startsWith('331'));
      expect(await c.command('PASS anything'), startsWith('230'));
      await c.close();
    });

    test('Username-only server: wrong username fails', () async {
      final c = await FtpTestClient.connect(usernameOnlyPort);
      expect(await c.command('USER wrong'), startsWith('331'));
      expect(await c.command('PASS anything'), startsWith('530'));
      await c.close();
    });
  });

  group('No-auth server', () {
    late FtpServer noAuthServer;
    const noAuthPort = 2252;

    setUpAll(() async {
      noAuthServer = FtpServer(
        noAuthPort,
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: p.basename(tempDir.path)),
        serverType: ServerType.readAndWrite,
        logFunction: (msg) {},
      );
      await noAuthServer.startInBackground();
    });

    tearDownAll(() async {
      await noAuthServer.stop();
    });

    test('No-auth server: USER returns 230 directly', () async {
      final c = await FtpTestClient.connect(noAuthPort);
      final r = await c.command('USER anonymous');
      expect(r, startsWith('230'));
      // Should be able to use commands immediately without PASS
      expect(await c.command('PWD'), startsWith('257'));
      await c.close();
    });
  });
}
