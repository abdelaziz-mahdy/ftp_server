// ignore_for_file: avoid_print
import 'dart:io';
import 'package:ftp_server/tls_config.dart';
import 'package:test/test.dart';

void main() {
  group('TlsConfig', () {
    test('builds SecurityContext from PEM files', () {
      final config = TlsConfig(
        certFilePath: 'test/test_certs/cert.pem',
        keyFilePath: 'test/test_certs/key.pem',
      );
      final ctx = config.buildContext();
      expect(ctx, isA<SecurityContext>());
    });

    test('throws if no cert and no securityContext', () {
      expect(() => TlsConfig(), throwsArgumentError);
    });

    test('throws if certFilePath without keyFilePath', () {
      expect(
        () => TlsConfig(certFilePath: 'cert.pem'),
        throwsArgumentError,
      );
    });

    test('accepts pre-built SecurityContext', () {
      final ctx = SecurityContext();
      final config = TlsConfig(securityContext: ctx);
      expect(config.buildContext(), same(ctx));
    });

    test('throws if requireClientCert without trustedCerts or context', () {
      expect(
        () => TlsConfig(
          certFilePath: 'test/test_certs/cert.pem',
          keyFilePath: 'test/test_certs/key.pem',
          requireClientCert: true,
        ),
        throwsArgumentError,
      );
    });

    test('requireClientCert with trustedCertificatesPath succeeds', () {
      final config = TlsConfig(
        certFilePath: 'test/test_certs/cert.pem',
        keyFilePath: 'test/test_certs/key.pem',
        requireClientCert: true,
        trustedCertificatesPath: 'test/test_certs/cert.pem',
      );
      expect(config.buildContext(), isA<SecurityContext>());
    });
  });

  group('FtpSecurityMode', () {
    test('has three values', () {
      expect(FtpSecurityMode.values.length, 3);
      expect(FtpSecurityMode.values, contains(FtpSecurityMode.none));
      expect(FtpSecurityMode.values, contains(FtpSecurityMode.explicit));
      expect(FtpSecurityMode.values, contains(FtpSecurityMode.implicit));
    });
  });

  group('ProtectionLevel', () {
    test('has two values', () {
      expect(ProtectionLevel.values.length, 2);
      expect(ProtectionLevel.values, contains(ProtectionLevel.clear));
      expect(ProtectionLevel.values, contains(ProtectionLevel.private_));
    });
  });
}
