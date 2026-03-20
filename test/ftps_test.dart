// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/tls_config.dart';
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
}
