import 'dart:io';

enum FtpSecurityMode { none, explicit, implicit }

enum ProtectionLevel { clear, private_ }

class TlsConfig {
  final String? certFilePath;
  final String? keyFilePath;
  final String? trustedCertificatesPath;
  final SecurityContext? securityContext;
  final bool requireClientCert;

  TlsConfig({
    this.certFilePath,
    this.keyFilePath,
    this.trustedCertificatesPath,
    this.securityContext,
    this.requireClientCert = false,
  }) {
    if (securityContext == null) {
      if (certFilePath == null || keyFilePath == null) {
        throw ArgumentError(
          'Either securityContext or both certFilePath and keyFilePath must be provided',
        );
      }
    }
    if (requireClientCert &&
        securityContext == null &&
        trustedCertificatesPath == null) {
      throw ArgumentError(
        'requireClientCert requires trustedCertificatesPath or a pre-built securityContext',
      );
    }
  }

  SecurityContext buildContext() {
    if (securityContext != null) return securityContext!;
    final ctx = SecurityContext();
    ctx.useCertificateChain(certFilePath!);
    ctx.usePrivateKey(keyFilePath!);
    if (trustedCertificatesPath != null) {
      ctx.setTrustedCertificates(trustedCertificatesPath!);
    }
    return ctx;
  }
}
