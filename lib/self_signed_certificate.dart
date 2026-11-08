import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:ftp_server/tls_config.dart';

/// A self-signed TLS certificate for running FTPS without any setup.
///
/// Generate one with [SelfSignedCertificate.generate], store
/// [certificatePem] and [privateKeyPem] wherever your app keeps its data,
/// and recreate it on the next start with the default constructor. Reusing
/// the same certificate means FTP clients that trusted it once (for example
/// FileZilla's "Always trust this certificate") don't warn again.
///
/// ```dart
/// final cert = SelfSignedCertificate.generate();
/// // Save cert.certificatePem and cert.privateKeyPem, then later:
/// final saved = SelfSignedCertificate(
///   certificatePem: savedCertPem,
///   privateKeyPem: savedKeyPem,
/// );
/// final server = FtpServer(
///   2121,
///   fileOperations: ...,
///   serverType: ServerType.readAndWrite,
///   securityMode: FtpSecurityMode.explicit,
///   tlsConfig: saved.toTlsConfig(),
/// );
/// print('Certificate fingerprint: ${saved.sha256Fingerprint}');
/// ```
///
/// Clients cannot verify a self-signed certificate against a certificate
/// authority. Show [sha256Fingerprint] to your users so they can compare it
/// with the fingerprint their FTP client displays on first connect.
class SelfSignedCertificate {
  /// The PEM-encoded certificate.
  final String certificatePem;

  /// The PEM-encoded private key that belongs to [certificatePem].
  final String privateKeyPem;

  /// Wraps a certificate and key previously created by [generate] (or any
  /// other PEM-encoded certificate and matching key).
  const SelfSignedCertificate({
    required this.certificatePem,
    required this.privateKeyPem,
  });

  /// Generates a new self-signed certificate with an ECDSA P-256 key.
  ///
  /// [commonName] is the certificate's subject CN, [dnsNames] are added as
  /// subject alternative names, and the certificate is valid from one hour
  /// ago (to tolerate clock differences) for [validity].
  factory SelfSignedCertificate.generate({
    String commonName = 'ftp_server',
    List<String> dnsNames = const ['localhost'],
    Duration validity = const Duration(days: 3650),
  }) {
    if (validity.inDays < 1) {
      throw ArgumentError.value(
          validity, 'validity', 'must be at least one day');
    }
    final keyPair = CryptoUtils.generateEcKeyPair();
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final publicKey = keyPair.publicKey as ECPublicKey;

    final csr = X509Utils.generateEccCsrPem(
      {'CN': commonName},
      privateKey,
      publicKey,
    );
    final certificatePem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      validity.inDays,
      sans: dnsNames.isEmpty ? null : dnsNames,
      serialNumber: _randomSerialNumber(),
      notBefore: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    );
    return SelfSignedCertificate(
      certificatePem: certificatePem,
      privateKeyPem: CryptoUtils.encodeEcPrivateKeyToPem(privateKey),
    );
  }

  /// The SHA-256 fingerprint of the certificate, as colon-separated
  /// uppercase hex (the format `openssl x509 -fingerprint -sha256` prints).
  ///
  /// FTP clients show this value when they ask the user to trust the
  /// certificate (FileZilla in lowercase).
  String get sha256Fingerprint {
    final der = CryptoUtils.getBytesFromPEMString(certificatePem);
    final hex = CryptoUtils.getHash(der, algorithmName: 'SHA-256');
    final pairs = <String>[];
    for (var i = 0; i < hex.length; i += 2) {
      pairs.add(hex.substring(i, i + 2));
    }
    return pairs.join(':');
  }

  /// A [TlsConfig] that serves this certificate.
  TlsConfig toTlsConfig() => TlsConfig.fromPem(
        certificatePem: certificatePem,
        privateKeyPem: privateKeyPem,
      );

  // A random positive 63-bit serial number, so regenerated certificates
  // don't share a serial (clients may cache certificates by serial).
  static String _randomSerialNumber() {
    final random = Random.secure();
    var serial = BigInt.from(random.nextInt(1 << 30) + 1);
    serial = (serial << 32) | BigInt.from(random.nextInt(1 << 32));
    return serial.toString();
  }
}
