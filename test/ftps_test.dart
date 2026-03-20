// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Test client that supports upgrading to TLS (for explicit FTPS testing).
class FtpTlsTestClient {
  Socket _socket;
  final StringBuffer _buffer = StringBuffer();
  final StreamController<void> _dataReady = StreamController<void>.broadcast();
  StreamSubscription? _sub;

  FtpTlsTestClient._(this._socket) {
    _attachListener();
  }

  void _attachListener() {
    _sub = _socket.listen((data) {
      _buffer.write(utf8.decode(data));
      _dataReady.add(null);
    }, onDone: () {
      _dataReady.close();
    });
  }

  static Future<FtpTlsTestClient> connect(int port) async {
    final socket = await Socket.connect('127.0.0.1', port);
    final client = FtpTlsTestClient._(socket);
    await client.readResponse(); // consume 220 welcome
    return client;
  }

  Future<void> upgradeTls() async {
    // Pause (not cancel) the existing listener so the underlying socket stays
    // open while SecureSocket.secure() performs the TLS handshake.
    _sub?.pause();
    _socket = await SecureSocket.secure(
      _socket,
      onBadCertificate: (_) => true,
    );
    _attachListener();
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

  /// Perform AUTH TLS + TLS upgrade + PBSZ 0.
  Future<void> authAndPbsz() async {
    send('AUTH TLS');
    await readResponse(); // 234
    await upgradeTls();
    send('PBSZ 0');
    await readResponse(); // 200
  }

  /// Perform AUTH TLS + TLS upgrade + PBSZ 0 + PROT P.
  Future<void> authPbszProtP() async {
    await authAndPbsz();
    send('PROT P');
    await readResponse(); // 200
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _socket.close();
  }
}

void main() {
  late Directory tempDir;

  final certPath =
      p.join(Directory.current.path, 'test', 'test_certs', 'cert.pem');
  final keyPath =
      p.join(Directory.current.path, 'test', 'test_certs', 'key.pem');

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('ftps_test_');
    File('${tempDir.path}/hello.txt').writeAsStringSync('Hello!');
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  // ── Group 1: AUTH on plain server ──────────────────────────────────────

  group('AUTH on plain server', () {
    late FtpServer server;
    const int port = 2260;

    setUpAll(() async {
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
    });

    test('AUTH TLS returns 504 on plain server', () async {
      final c = await FtpTlsTestClient.connect(port);
      final r = await c.command('AUTH TLS');
      expect(r, startsWith('504'));
      await c.close();
    });

    test('AUTH SSL returns 504 on plain server', () async {
      final c = await FtpTlsTestClient.connect(port);
      final r = await c.command('AUTH SSL');
      expect(r, startsWith('504'));
      await c.close();
    });
  });

  // ── Group 2: Explicit FTPS server ─────────────────────────────────────
  // Groups 2-4, 6-8 all share the same explicit server on port 2261.

  group('Explicit FTPS server', () {
    late FtpServer server;
    const int port = 2261;

    setUpAll(() async {
      server = FtpServer(
        port,
        username: 'testuser',
        password: 'testpass',
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: p.basename(tempDir.path)),
        serverType: ServerType.readAndWrite,
        securityMode: FtpSecurityMode.explicit,
        tlsConfig: TlsConfig(certFilePath: certPath, keyFilePath: keyPath),
        logFunction: (msg) {},
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
    });

    // ── AUTH ──

    group('AUTH', () {
      test('AUTH TLS returns 234 and TLS upgrade succeeds', () async {
        final c = await FtpTlsTestClient.connect(port);
        final r = await c.command('AUTH TLS');
        expect(r, startsWith('234'));
        await c.upgradeTls();
        // After TLS upgrade, commands should still work
        final syst = await c.command('SYST');
        expect(syst, startsWith('215'));
        await c.close();
      });

      test('AUTH TLS-C returns 234', () async {
        final c = await FtpTlsTestClient.connect(port);
        final r = await c.command('AUTH TLS-C');
        expect(r, startsWith('234'));
        await c.close();
      });

      test('AUTH GSSAPI returns 504', () async {
        final c = await FtpTlsTestClient.connect(port);
        final r = await c.command('AUTH GSSAPI');
        expect(r, startsWith('504'));
        await c.close();
      });

      test('AUTH when TLS already active returns 503', () async {
        final c = await FtpTlsTestClient.connect(port);
        c.send('AUTH TLS');
        await c.readResponse(); // 234
        await c.upgradeTls();
        final r = await c.command('AUTH TLS');
        expect(r, startsWith('503'));
        await c.close();
      });

      test('After AUTH TLS, commands require re-auth (PWD returns 530)',
          () async {
        final c = await FtpTlsTestClient.connect(port);
        c.send('AUTH TLS');
        await c.readResponse(); // 234
        await c.upgradeTls();
        // AUTH causes reinitialize(), so user is no longer authenticated
        final r = await c.command('PWD');
        expect(r, startsWith('530'));
        await c.close();
      });
    });

    // ── PBSZ ──

    group('PBSZ', () {
      test('PBSZ 0 after AUTH returns 200', () async {
        final c = await FtpTlsTestClient.connect(port);
        c.send('AUTH TLS');
        await c.readResponse(); // 234
        await c.upgradeTls();
        final r = await c.command('PBSZ 0');
        expect(r, startsWith('200'));
        await c.close();
      });

      test('PBSZ before AUTH returns 503', () async {
        final c = await FtpTlsTestClient.connect(port);
        final r = await c.command('PBSZ 0');
        expect(r, startsWith('503'));
        await c.close();
      });

      test('PBSZ 1024 returns 501', () async {
        final c = await FtpTlsTestClient.connect(port);
        c.send('AUTH TLS');
        await c.readResponse(); // 234
        await c.upgradeTls();
        final r = await c.command('PBSZ 1024');
        expect(r, startsWith('501'));
        await c.close();
      });
    });

    // ── PROT ──

    group('PROT', () {
      test('PROT P returns 200', () async {
        final c = await FtpTlsTestClient.connect(port);
        await c.authAndPbsz();
        final r = await c.command('PROT P');
        expect(r, startsWith('200'));
        await c.close();
      });

      test('PROT C returns 200 (requireEncryptedData=false)', () async {
        final c = await FtpTlsTestClient.connect(port);
        await c.authAndPbsz();
        final r = await c.command('PROT C');
        expect(r, startsWith('200'));
        await c.close();
      });

      test('PROT S returns 504', () async {
        final c = await FtpTlsTestClient.connect(port);
        await c.authAndPbsz();
        final r = await c.command('PROT S');
        expect(r, startsWith('504'));
        await c.close();
      });

      test('PROT E returns 504', () async {
        final c = await FtpTlsTestClient.connect(port);
        await c.authAndPbsz();
        final r = await c.command('PROT E');
        expect(r, startsWith('504'));
        await c.close();
      });

      test('PROT before PBSZ returns 503', () async {
        final c = await FtpTlsTestClient.connect(port);
        c.send('AUTH TLS');
        await c.readResponse(); // 234
        await c.upgradeTls();
        final r = await c.command('PROT P');
        expect(r, startsWith('503'));
        await c.close();
      });

      test('PROT before AUTH returns 503', () async {
        final c = await FtpTlsTestClient.connect(port);
        final r = await c.command('PROT P');
        expect(r, startsWith('503'));
        await c.close();
      });
    });

    // ── CCC ──

    group('CCC', () {
      test('CCC returns 534', () async {
        final c = await FtpTlsTestClient.connect(port);
        final r = await c.command('CCC');
        expect(r, startsWith('534'));
        await c.close();
      });
    });

    // ── REIN under TLS ──

    group('REIN under TLS', () {
      test('REIN when TLS active returns 502', () async {
        final c = await FtpTlsTestClient.connect(port);
        c.send('AUTH TLS');
        await c.readResponse(); // 234
        await c.upgradeTls();
        final r = await c.command('REIN');
        expect(r, startsWith('502'));
        await c.close();
      });
    });

    // ── FEAT ──

    group('FEAT', () {
      test('FEAT on explicit server includes AUTH TLS, PBSZ, PROT', () async {
        final c = await FtpTlsTestClient.connect(port);
        c.send('FEAT');
        final r = await c.readMultiLineResponse();
        expect(r, contains('AUTH TLS'));
        expect(r, contains('PBSZ'));
        expect(r, contains('PROT'));
        await c.close();
      });
    });
  });

  // ── FEAT on plain server ──────────────────────────────────────────────

  group('FEAT on plain server', () {
    late FtpServer server;
    const int port = 2263;

    setUpAll(() async {
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
    });

    test('FEAT does NOT include AUTH TLS', () async {
      final c = await FtpTlsTestClient.connect(port);
      c.send('FEAT');
      final r = await c.readMultiLineResponse();
      expect(r, isNot(contains('AUTH TLS')));
      expect(r, isNot(contains('PBSZ')));
      expect(r, isNot(contains('PROT')));
      await c.close();
    });
  });

  // ── Group 5 & 9: requireEncryptedData=true server ─────────────────────

  group('requireEncryptedData=true server', () {
    late FtpServer server;
    const int port = 2262;

    setUpAll(() async {
      server = FtpServer(
        port,
        username: 'testuser',
        password: 'testpass',
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: p.basename(tempDir.path)),
        serverType: ServerType.readAndWrite,
        securityMode: FtpSecurityMode.explicit,
        tlsConfig: TlsConfig(certFilePath: certPath, keyFilePath: keyPath),
        requireEncryptedData: true,
        logFunction: (msg) {},
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
    });

    test('PROT C returns 534', () async {
      final c = await FtpTlsTestClient.connect(port);
      await c.authAndPbsz();
      final r = await c.command('PROT C');
      expect(r, startsWith('534'));
      await c.close();
    });

    test('LIST without PROT P returns 521', () async {
      final c = await FtpTlsTestClient.connect(port);
      await c.authAndPbsz();
      await c.login();
      // No PROT P issued — data protection is Clear, server requires Private
      final r = await c.command('LIST');
      expect(r, startsWith('521'));
      await c.close();
    });
  });

  // ── Implicit mode integration ───────────────────────────────────────

  group('Implicit mode integration', () {
    late FtpServer server;
    const int port = 2264;

    setUpAll(() async {
      server = FtpServer(
        port,
        username: 'testuser',
        password: 'testpass',
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: p.basename(tempDir.path)),
        serverType: ServerType.readAndWrite,
        securityMode: FtpSecurityMode.implicit,
        tlsConfig: TlsConfig(certFilePath: certPath, keyFilePath: keyPath),
        logFunction: (msg) {},
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
    });

    test('Connect and authenticate over TLS', () async {
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        port,
        onBadCertificate: (_) => true,
      );
      final client = FtpTlsTestClient._(socket);
      final welcome = await client.readResponse();
      expect(welcome, startsWith('220'));

      final userResp = await client.command('USER testuser');
      expect(userResp, startsWith('331'));

      final passResp = await client.command('PASS testpass');
      expect(passResp, startsWith('230'));

      final pwdResp = await client.command('PWD');
      expect(pwdResp, startsWith('257'));

      await client.close();
    });

    test('Data transfer over TLS', () async {
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        port,
        onBadCertificate: (_) => true,
      );
      final client = FtpTlsTestClient._(socket);
      await client.readResponse(); // 220

      await client.login();

      final pbszResp = await client.command('PBSZ 0');
      expect(pbszResp, startsWith('200'));

      final protResp = await client.command('PROT P');
      expect(protResp, startsWith('200'));

      final epsvResp = await client.command('EPSV');
      expect(epsvResp, startsWith('229'));
      final match = RegExp(r'\|\|\|(\d+)\|').firstMatch(epsvResp);
      expect(match, isNotNull);
      final dataPort = int.parse(match!.group(1)!);

      // Send LIST, then connect to data port
      client.send('LIST');

      final dataSocket = await SecureSocket.connect(
        '127.0.0.1',
        dataPort,
        onBadCertificate: (_) => true,
      );

      final dataBuffer = StringBuffer();
      await for (final chunk in dataSocket) {
        dataBuffer.write(utf8.decode(chunk));
      }

      // Data socket closes when transfer is done
      final listData = dataBuffer.toString();
      expect(listData, isNotEmpty);

      // Read 150 and 226 from control connection
      final r1 = await client.readResponse();
      if (r1.startsWith('150')) {
        final r2 = await client.readResponse();
        expect(r2, startsWith('226'));
      } else {
        expect(r1, startsWith('226'));
      }

      await client.close();
    });
  });

  // ── Explicit mode full flow ─────────────────────────────────────────

  group('Explicit mode full flow', () {
    late FtpServer server;
    const int flowPort = 2265;

    setUpAll(() async {
      server = FtpServer(
        flowPort,
        username: 'testuser',
        password: 'testpass',
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: p.basename(tempDir.path)),
        serverType: ServerType.readAndWrite,
        securityMode: FtpSecurityMode.explicit,
        tlsConfig: TlsConfig(certFilePath: certPath, keyFilePath: keyPath),
        logFunction: (msg) {},
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
    });

    test('Full encrypted flow with PROT P', () async {
      final c = await FtpTlsTestClient.connect(flowPort);

      // AUTH TLS + upgrade
      final authResp = await c.command('AUTH TLS');
      expect(authResp, startsWith('234'));
      await c.upgradeTls();

      // Authenticate
      final userResp = await c.command('USER testuser');
      expect(userResp, startsWith('331'));
      final passResp = await c.command('PASS testpass');
      expect(passResp, startsWith('230'));

      // Set up protected data channel
      final pbszResp = await c.command('PBSZ 0');
      expect(pbszResp, startsWith('200'));
      final protResp = await c.command('PROT P');
      expect(protResp, startsWith('200'));

      // EPSV to get data port
      final epsvResp = await c.command('EPSV');
      expect(epsvResp, startsWith('229'));
      final match = RegExp(r'\|\|\|(\d+)\|').firstMatch(epsvResp);
      expect(match, isNotNull);
      final dataPort = int.parse(match!.group(1)!);

      // Send LIST, connect to data port with TLS
      c.send('LIST');

      final dataSocket = await SecureSocket.connect(
        '127.0.0.1',
        dataPort,
        onBadCertificate: (_) => true,
      );

      final dataBuffer = StringBuffer();
      await for (final chunk in dataSocket) {
        dataBuffer.write(utf8.decode(chunk));
      }
      expect(dataBuffer.toString(), isNotEmpty);

      final r1 = await c.readResponse();
      if (r1.startsWith('150')) {
        final r2 = await c.readResponse();
        expect(r2, startsWith('226'));
      } else {
        expect(r1, startsWith('226'));
      }

      await c.close();
    });

    test('Clear data channel with PROT C', () async {
      final c = await FtpTlsTestClient.connect(flowPort);

      // AUTH TLS + upgrade
      final authResp = await c.command('AUTH TLS');
      expect(authResp, startsWith('234'));
      await c.upgradeTls();

      // Authenticate
      await c.login();

      // Set up clear data channel
      final pbszResp = await c.command('PBSZ 0');
      expect(pbszResp, startsWith('200'));
      final protResp = await c.command('PROT C');
      expect(protResp, startsWith('200'));

      // EPSV to get data port
      final epsvResp = await c.command('EPSV');
      expect(epsvResp, startsWith('229'));
      final match = RegExp(r'\|\|\|(\d+)\|').firstMatch(epsvResp);
      expect(match, isNotNull);
      final dataPort = int.parse(match!.group(1)!);

      // Send LIST, connect to data port with plain socket
      c.send('LIST');

      final dataSocket = await Socket.connect('127.0.0.1', dataPort);

      final dataBuffer = StringBuffer();
      await for (final chunk in dataSocket) {
        dataBuffer.write(utf8.decode(chunk));
      }
      expect(dataBuffer.toString(), isNotEmpty);

      final r1 = await c.readResponse();
      if (r1.startsWith('150')) {
        final r2 = await c.readResponse();
        expect(r2, startsWith('226'));
      } else {
        expect(r1, startsWith('226'));
      }

      await c.close();
    });
  });

  // ── TLS error handling ──────────────────────────────────────────────

  group('TLS error handling', () {
    late FtpServer server;
    const int port = 2266;

    setUpAll(() async {
      server = FtpServer(
        port,
        username: 'testuser',
        password: 'testpass',
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: p.basename(tempDir.path)),
        serverType: ServerType.readAndWrite,
        securityMode: FtpSecurityMode.explicit,
        tlsConfig: TlsConfig(certFilePath: certPath, keyFilePath: keyPath),
        logFunction: (msg) {},
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
    });

    test('TLS handshake failure — server survives', () async {
      // Connect and request AUTH TLS, then close without completing handshake
      final rawSocket = await Socket.connect('127.0.0.1', port);
      final buf = StringBuffer();
      rawSocket.listen((data) {
        buf.write(utf8.decode(data));
      });
      // Wait for 220 welcome
      await Future.delayed(const Duration(milliseconds: 500));

      rawSocket.write('AUTH TLS\r\n');
      await Future.delayed(const Duration(milliseconds: 500));
      // 234 should be in buffer — now close without TLS handshake
      await rawSocket.close();
      rawSocket.destroy();

      // Wait briefly for server to handle the broken connection
      await Future.delayed(const Duration(seconds: 1));

      // Server should still accept new connections
      final c = await FtpTlsTestClient.connect(port);
      final syst = await c.command('SYST');
      expect(syst, startsWith('215'));
      await c.close();
    });
  });

  // ── Concurrent sessions ─────────────────────────────────────────────

  group('Concurrent sessions', () {
    late FtpServer server;
    const int port = 2267;

    setUpAll(() async {
      server = FtpServer(
        port,
        username: 'testuser',
        password: 'testpass',
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: p.basename(tempDir.path)),
        serverType: ServerType.readAndWrite,
        securityMode: FtpSecurityMode.explicit,
        tlsConfig: TlsConfig(certFilePath: certPath, keyFilePath: keyPath),
        logFunction: (msg) {},
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
    });

    test('One TLS, one plain — both work independently', () async {
      // Client A: does AUTH TLS + upgrade
      final clientA = await FtpTlsTestClient.connect(port);
      final authResp = await clientA.command('AUTH TLS');
      expect(authResp, startsWith('234'));
      await clientA.upgradeTls();

      // Client B: stays plain
      final clientB = await FtpTlsTestClient.connect(port);

      // Both send SYST independently
      final systA = await clientA.command('SYST');
      expect(systA, startsWith('215'));

      final systB = await clientB.command('SYST');
      expect(systB, startsWith('215'));

      await clientA.close();
      await clientB.close();
    });
  });
}
