// lib/services/certificate_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
// lib/model/stored_security_context.dart

class StoredSecurityContext {
  final String privateKey; // PEM-formatted private key
  final String publicKey; // PEM-formatted public key
  final String certificate; // PEM-formatted certificate
  final String certificateHash; // SHA-256 hash of the certificate

  StoredSecurityContext({
    required this.privateKey,
    required this.publicKey,
    required this.certificate,
    required this.certificateHash,
  });

  /// Creates and returns a [SecurityContext] from this stored security context.
  SecurityContext createSecurityContext() {
    return SecurityContext()
      ..usePrivateKeyBytes(privateKey.codeUnits)
      ..useCertificateChainBytes(certificate.codeUnits);
  }
}

class CertificateService {
  /// Generates a random [StoredSecurityContext].
  static StoredSecurityContext generateSecurityContext(
      [AsymmetricKeyPair? keyPair]) {
    keyPair ??= CryptoUtils.generateRSAKeyPair();
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final dn = {
      'CN': 'Ftp User',
      'O': 'Your Organization',
      'OU': 'Your Organizational Unit',
      'L': 'Your City',
      'S': 'Your State',
      'C': 'Your Country Code',
    };

    final csr = X509Utils.generateRsaCsrPem(dn, privateKey, publicKey);
    final certificate = X509Utils.generateSelfSignedCertificate(
      keyPair.privateKey,
      csr,
      365 * 10, // Valid for 10 years
    );
    final hash = calculateHashOfCertificate(certificate);

    return StoredSecurityContext(
      privateKey: CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey),
      publicKey: CryptoUtils.encodeRSAPublicKeyToPemPkcs1(publicKey),
      certificate: certificate,
      certificateHash: hash,
    );
  }

  /// Calculates the SHA-256 hash of a certificate.
  static String calculateHashOfCertificate(String certificate) {
    // Convert PEM to DER
    final pemContent = certificate
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((line) => line.isNotEmpty && !line.startsWith('---'))
        .join();
    final der = base64Decode(pemContent);

    // Calculate hash
    return CryptoUtils.getHash(
      Uint8List.fromList(der),
      algorithmName: 'SHA-256',
    );
  }
}
