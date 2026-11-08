// Mutual TLS: TlsConfig(requireClientCert: true) must make the server
// request and verify a client certificate on every TLS handshake (implicit
// listener, AUTH TLS upgrade and PROT P data connections).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _certDir = p.join(Directory.current.path, 'test', 'test_certs');

SecurityContext _clientContext(SelfSignedCertificate? cert) {
  final ctx = SecurityContext(withTrustedRoots: false);
  if (cert != null) {
    ctx
      ..useCertificateChainBytes(utf8.encode(cert.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(cert.privateKeyPem));
  }
  return ctx;
}

/// Line reader over a socket that also reports errors and closure as null.
class _Lines {
  final StreamIterator<String> _it;
  _Lines(Stream<List<int>> s)
      : _it = StreamIterator(s
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()));

  Future<String?> next() async {
    try {
      final has = await _it.moveNext().timeout(const Duration(seconds: 5));
      return has ? _it.current : null;
    } catch (_) {
      return null;
    }
  }
}

/// Runs a client connection attempt and returns its result, or null if it
/// fails with a socket/TLS error. After a refused handshake, dart:io can
/// report the server's connection reset later, outside any listener; this
/// zone absorbs those expected errors so they don't fail the test. Any other
/// error still fails it.
Future<String?> _attempt(Future<String?> Function() body) {
  final result = Completer<String?>();
  runZonedGuarded(() async {
    final value = await body();
    if (!result.isCompleted) result.complete(value);
  }, (error, stack) {
    final expected = error is SocketException ||
        error is TlsException ||
        error is TimeoutException;
    if (!expected) {
      if (!result.isCompleted) result.completeError(error, stack);
      return;
    }
    if (!result.isCompleted) result.complete(null);
  });
  return result.future;
}

/// Connects to an implicit FTPS server and returns the greeting, or null if
/// the TLS handshake (or the connection right after it) is refused.
Future<String?> _implicitGreeting(int port, SecurityContext ctx) =>
    _attempt(() async {
      final socket = await SecureSocket.connect('127.0.0.1', port,
          context: ctx, onBadCertificate: (_) => true);
      addTearDown(socket.destroy);
      return _Lines(socket).next();
    });

/// Upgrades a plain connection with AUTH TLS and returns the NOOP reply,
/// or null if the server refuses the TLS handshake.
Future<String?> _explicitNoop(int port, SecurityContext ctx) =>
    _attempt(() => _explicitNoopInner(port, ctx));

Future<String?> _explicitNoopInner(int port, SecurityContext ctx) async {
  final plain = await Socket.connect('127.0.0.1', port);
  addTearDown(plain.destroy);
  // When the server refuses the handshake it may reset the TCP connection.
  // That reset can surface on the plain socket's subscription or its done
  // future; both are expected here, so don't let them escape as unhandled.
  plain.done.then((_) {}, onError: (_) {});
  final buffer = StringBuffer();
  final got234 = Completer<void>();
  final sub = plain.listen(
    (data) {
      buffer.write(utf8.decode(data));
      if (buffer.toString().contains('234 ') && !got234.isCompleted) {
        got234.complete();
      }
    },
    onError: (_) {},
  );
  plain.write('AUTH TLS\r\n');
  await got234.future.timeout(const Duration(seconds: 5));
  sub.pause();
  final secure = await SecureSocket.secure(plain,
      context: ctx, onBadCertificate: (_) => true);
  addTearDown(secure.destroy);
  final lines = _Lines(secure);
  secure.write('NOOP\r\n');
  return lines.next();
}

void main() {
  late Directory root;
  late SelfSignedCertificate trustedClient;
  late SelfSignedCertificate untrustedClient;
  late String trustedPath;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('ftps_mtls_');
    File(p.join(root.path, 'hello.txt')).writeAsStringSync('Hello!');
    trustedClient = SelfSignedCertificate.generate(commonName: 'client');
    untrustedClient = SelfSignedCertificate.generate(commonName: 'intruder');
    trustedPath = p.join(root.path, 'trusted_clients.pem');
    File(trustedPath).writeAsStringSync(trustedClient.certificatePem);
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  FtpServer mtlsServer(int port, FtpSecurityMode mode) => FtpServer(
        port,
        fileOperations: PhysicalFileOperations(root.path),
        serverType: ServerType.readOnly,
        securityMode: mode,
        tlsConfig: TlsConfig(
          certFilePath: p.join(_certDir, 'cert.pem'),
          keyFilePath: p.join(_certDir, 'key.pem'),
          requireClientCert: true,
          trustedCertificatesPath: trustedPath,
        ),
        logFunction: (_) {},
      );

  group('implicit FTPS with requireClientCert', () {
    const port = 2285;
    late FtpServer server;

    setUpAll(() async {
      server = mtlsServer(port, FtpSecurityMode.implicit);
      await server.startInBackground();
    });
    tearDownAll(() => server.stop());

    test('accepts a trusted client certificate', () async {
      expect(await _implicitGreeting(port, _clientContext(trustedClient)),
          startsWith('220'));
    });

    test('refuses a client without a certificate', () async {
      expect(await _implicitGreeting(port, _clientContext(null)), isNull);
    });

    test('refuses an untrusted client certificate', () async {
      expect(await _implicitGreeting(port, _clientContext(untrustedClient)),
          isNull);
    });

    test('requires the client certificate on the data connection', () async {
      final ctx = _clientContext(trustedClient);
      final control = await SecureSocket.connect('127.0.0.1', port,
          context: ctx, onBadCertificate: (_) => true);
      addTearDown(control.destroy);
      final lines = _Lines(control);
      expect(await lines.next(), startsWith('220'));

      Future<String?> cmd(String c) {
        control.write('$c\r\n');
        return lines.next();
      }

      Future<int> pasvPort() async {
        final r = (await cmd('PASV'))!;
        final m = RegExp(r'\(\d+,\d+,\d+,\d+,(\d+),(\d+)\)').firstMatch(r)!;
        return int.parse(m.group(1)!) * 256 + int.parse(m.group(2)!);
      }

      // With the trusted certificate the listing works.
      var raw = await Socket.connect('127.0.0.1', await pasvPort());
      control.write('NLST\r\n');
      expect(await lines.next(), startsWith('150'));
      final data = await SecureSocket.secure(raw,
          context: ctx, onBadCertificate: (_) => true);
      final listing = await utf8.decoder.bind(data.cast<List<int>>()).join();
      expect(listing, contains('hello.txt'));
      expect(await lines.next(), startsWith('226'));

      // Without a certificate the data handshake is refused with 522.
      raw = await Socket.connect('127.0.0.1', await pasvPort());
      addTearDown(raw.destroy);
      control.write('NLST\r\n');
      expect(await lines.next(), startsWith('150'));
      try {
        final s = await SecureSocket.secure(raw,
            context: _clientContext(null), onBadCertificate: (_) => true);
        await s.drain<void>().catchError((_) {});
      } catch (_) {}
      expect(await lines.next(), startsWith('522'));
    });
  });

  group('explicit FTPS with requireClientCert', () {
    const port = 2286;
    late FtpServer server;

    setUpAll(() async {
      server = mtlsServer(port, FtpSecurityMode.explicit);
      await server.startInBackground();
    });
    tearDownAll(() => server.stop());

    test('AUTH TLS accepts a trusted client certificate', () async {
      expect(await _explicitNoop(port, _clientContext(trustedClient)),
          startsWith('200'));
    });

    test('AUTH TLS refuses a client without a certificate', () async {
      expect(await _explicitNoop(port, _clientContext(null)), isNull);
    });

    test('AUTH TLS refuses an untrusted client certificate', () async {
      expect(
          await _explicitNoop(port, _clientContext(untrustedClient)), isNull);
    });
  });

  group('without requireClientCert', () {
    const port = 2287;
    late FtpServer server;

    setUpAll(() async {
      server = FtpServer(
        port,
        fileOperations: PhysicalFileOperations(root.path),
        serverType: ServerType.readOnly,
        securityMode: FtpSecurityMode.implicit,
        tlsConfig: TlsConfig(
          certFilePath: p.join(_certDir, 'cert.pem'),
          keyFilePath: p.join(_certDir, 'key.pem'),
        ),
        logFunction: (_) {},
      );
      await server.startInBackground();
    });
    tearDownAll(() => server.stop());

    test('accepts a client without a certificate', () async {
      expect(await _implicitGreeting(port, _clientContext(null)),
          startsWith('220'));
    });
  });

  test('implicit start() keeps serving after a failed TLS handshake', () async {
    const port = 2288;
    final server = FtpServer(
      port,
      fileOperations: PhysicalFileOperations(root.path),
      serverType: ServerType.readOnly,
      securityMode: FtpSecurityMode.implicit,
      tlsConfig: TlsConfig(
        certFilePath: p.join(_certDir, 'cert.pem'),
        keyFilePath: p.join(_certDir, 'key.pem'),
      ),
      logFunction: (_) {},
    );
    var stopped = false;
    final running = server.start().then((_) => stopped = true);

    // Wait until the port accepts connections, then send plain text
    // instead of a TLS ClientHello.
    Socket? plain;
    for (var i = 0; i < 50 && plain == null; i++) {
      try {
        plain = await Socket.connect('127.0.0.1', port);
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    expect(plain, isNotNull, reason: 'server did not start listening');
    plain!.write('USER anonymous\r\n');
    await plain.flush();
    await plain.drain<void>().catchError((_) {});
    plain.destroy();

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(stopped, isFalse, reason: 'a failed handshake stopped the server');
    expect(
        await _implicitGreeting(port, _clientContext(null)), startsWith('220'));

    await server.stop();
    await running.timeout(const Duration(seconds: 5));
    expect(stopped, isTrue);
  });
}
