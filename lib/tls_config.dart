import 'dart:io';

/// The security mode for the FTP server.
///
/// Determines how TLS/SSL is used for the control connection.
enum FtpSecurityMode {
  /// Plain FTP with no encryption. This is the default.
  none,

  /// Explicit FTPS (RFC 4217). The server listens on a plain TCP port.
  /// Clients upgrade to TLS by sending the `AUTH TLS` command.
  explicit,

  /// Implicit FTPS. The server listens on a TLS-encrypted port
  /// (typically 990). All connections are encrypted from the start.
  implicit,
}

/// The data channel protection level for FTPS sessions (RFC 4217 §9).
///
/// Set via the `PROT` command after `AUTH TLS` and `PBSZ 0`.
enum ProtectionLevel {
  /// Clear (unencrypted) data channel. Set via `PROT C`.
  clear,

  /// Private (TLS-encrypted) data channel. Set via `PROT P`.
  private_,
}

/// Configuration for TLS/SSL in the FTP server.
///
/// Provide either PEM file paths ([certFilePath] + [keyFilePath]) or a
/// pre-built [securityContext]. For mutual TLS (client certificate
/// validation), set [requireClientCert] to `true` and provide
/// [trustedCertificatesPath] or a [securityContext] with trusted CAs.
///
/// Example with PEM files:
/// ```dart
/// final config = TlsConfig(
///   certFilePath: '/path/to/cert.pem',
///   keyFilePath: '/path/to/key.pem',
/// );
/// ```
///
/// Example with pre-built SecurityContext:
/// ```dart
/// final ctx = SecurityContext()
///   ..useCertificateChain('cert.pem')
///   ..usePrivateKey('key.pem');
/// final config = TlsConfig(securityContext: ctx);
/// ```
class TlsConfig {
  /// Path to the PEM-encoded certificate chain file.
  ///
  /// Required when [securityContext] is not provided.
  final String? certFilePath;

  /// Path to the PEM-encoded private key file.
  ///
  /// Required when [securityContext] is not provided.
  final String? keyFilePath;

  /// Path to PEM-encoded trusted CA certificates for client certificate
  /// validation.
  ///
  /// Required when [requireClientCert] is `true` and [securityContext]
  /// is not provided.
  final String? trustedCertificatesPath;

  /// A pre-built [SecurityContext] for advanced use cases.
  ///
  /// When provided, [certFilePath], [keyFilePath], and
  /// [trustedCertificatesPath] are ignored. Use this for custom trust
  /// stores, PKCS12 certificates, or other advanced configurations.
  final SecurityContext? securityContext;

  /// Whether to require client certificates (mutual TLS).
  ///
  /// When `true`, the server requests and validates client certificates
  /// during the TLS handshake. Requires either [trustedCertificatesPath]
  /// or a [securityContext] configured with trusted CAs.
  ///
  /// Defaults to `false`.
  final bool requireClientCert;

  /// Creates a TLS configuration.
  ///
  /// Either [securityContext] or both [certFilePath] and [keyFilePath]
  /// must be provided. Throws [ArgumentError] if neither is set.
  ///
  /// If [requireClientCert] is `true`, either [trustedCertificatesPath]
  /// or [securityContext] must be provided.
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

  /// Builds and returns a [SecurityContext] from this configuration.
  ///
  /// If [securityContext] was provided, returns it directly.
  /// Otherwise, creates a new context from [certFilePath] and [keyFilePath].
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
