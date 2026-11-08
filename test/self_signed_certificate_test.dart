import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:test/test.dart';

final _fingerprintPattern = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');

String _fingerprintOfDer(List<int> der) {
  final hex = CryptoUtils.getHash(Uint8List.fromList(der));
  return [for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2)]
      .join(':');
}

/// Reads one complete reply line (e.g. "220 ...") from [lines].
Future<String> _reply(StreamIterator<String> lines) async {
  final hasLine = await lines.moveNext().timeout(const Duration(seconds: 5));
  expect(hasLine, isTrue, reason: 'connection closed before a reply');
  return lines.current;
}

void main() {
  group('SelfSignedCertificate.generate', () {
    late SelfSignedCertificate cert;

    setUpAll(() {
      cert = SelfSignedCertificate.generate();
    });

    test('returns PEM certificate and private key', () {
      expect(cert.certificatePem, startsWith('-----BEGIN CERTIFICATE-----'));
      expect(cert.privateKeyPem, contains('PRIVATE KEY-----'));
    });

    test('fingerprint is colon-separated uppercase SHA-256 hex', () {
      expect(cert.sha256Fingerprint, matches(_fingerprintPattern));
    });

    test('rebuilding from saved PEMs keeps the fingerprint', () {
      final saved = SelfSignedCertificate(
        certificatePem: cert.certificatePem,
        privateKeyPem: cert.privateKeyPem,
      );
      expect(saved.sha256Fingerprint, cert.sha256Fingerprint);
    });

    test('each call creates a different certificate', () {
      final other = SelfSignedCertificate.generate();
      expect(other.sha256Fingerprint, isNot(cert.sha256Fingerprint));
    });

    test('sets subject, SANs and validity', () {
      final custom = SelfSignedCertificate.generate(
        commonName: 'my-device',
        dnsNames: ['my-device.local', 'localhost'],
        validity: const Duration(days: 30),
      );
      final data = X509Utils.x509CertificateFromPem(custom.certificatePem);
      expect(data.tbsCertificate!.subject['2.5.4.3'], 'my-device');
      expect(data.tbsCertificate!.extensions!.subjectAlternativNames,
          containsAll(['my-device.local', 'localhost']));
      final notAfter = data.tbsCertificate!.validity.notAfter;
      final expected = DateTime.now().add(const Duration(days: 30));
      expect(notAfter.difference(expected).inHours.abs(), lessThan(2));
    });

    test('rejects a validity shorter than a day', () {
      expect(
        () =>
            SelfSignedCertificate.generate(validity: const Duration(hours: 1)),
        throwsArgumentError,
      );
    });
  });

  group('TlsConfig.fromPem', () {
    test('rejects a certificate that is not PEM', () {
      expect(
        () => TlsConfig.fromPem(
            certificatePem: 'not a certificate', privateKeyPem: 'nope'),
        throwsA(isA<TlsException>()),
      );
    });
  });

  group('FTPS server with a generated certificate', () {
    late Directory root;
    late SelfSignedCertificate cert;

    setUpAll(() {
      root = Directory.systemTemp.createTempSync('ftps_self_signed_');
      cert = SelfSignedCertificate.generate();
    });

    tearDownAll(() {
      root.deleteSync(recursive: true);
    });

    test('implicit FTPS serves the generated certificate', () async {
      const port = 2275;
      final server = FtpServer(
        port,
        fileOperations: PhysicalFileOperations(root.path),
        serverType: ServerType.readOnly,
        securityMode: FtpSecurityMode.implicit,
        tlsConfig: cert.toTlsConfig(),
        logFunction: (_) {},
      );
      await server.startInBackground();
      addTearDown(server.stop);

      X509Certificate? served;
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        port,
        onBadCertificate: (c) {
          served = c;
          return true;
        },
      );
      addTearDown(socket.destroy);
      final lines = StreamIterator(
          socket.cast<List<int>>().transform(utf8.decoder).transform(
                const LineSplitter(),
              ));

      expect(await _reply(lines), startsWith('220'));
      expect(served, isNotNull);
      expect(_fingerprintOfDer(served!.der), cert.sha256Fingerprint);
    });

    test('explicit FTPS upgrades with AUTH TLS', () async {
      const port = 2276;
      final server = FtpServer(
        port,
        fileOperations: PhysicalFileOperations(root.path),
        serverType: ServerType.readOnly,
        securityMode: FtpSecurityMode.explicit,
        tlsConfig: cert.toTlsConfig(),
        logFunction: (_) {},
      );
      await server.startInBackground();
      addTearDown(server.stop);

      final plain = await Socket.connect('127.0.0.1', port);
      // Read replies byte-wise until the 234, without consuming TLS bytes.
      final buffer = StringBuffer();
      final ready = Completer<void>();
      final sub = plain.listen((data) {
        buffer.write(utf8.decode(data));
        if (buffer.toString().contains('234') && !ready.isCompleted) {
          ready.complete();
        }
      });
      plain.write('AUTH TLS\r\n');
      await ready.future.timeout(const Duration(seconds: 5));
      expect(buffer.toString(), startsWith('220'));
      sub.pause();

      X509Certificate? served;
      final secure = await SecureSocket.secure(
        plain,
        onBadCertificate: (c) {
          served = c;
          return true;
        },
      );
      addTearDown(secure.destroy);
      expect(_fingerprintOfDer(served!.der), cert.sha256Fingerprint);

      final lines = StreamIterator(
          secure.cast<List<int>>().transform(utf8.decoder).transform(
                const LineSplitter(),
              ));
      secure.write('NOOP\r\n');
      expect(await _reply(lines), startsWith('200'));
    });
  });
}
