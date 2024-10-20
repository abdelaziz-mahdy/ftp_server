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
    final context = SecurityContext();

    try {
      // Load the certificate chain from the stored certificate
      context.useCertificateChainBytes(
        utf8.encode(certificate),
      );

      // Load the private key from the stored private key
      context.usePrivateKeyBytes(
        utf8.encode(privateKey),
      );
    } catch (e) {
      print('Error setting up SecurityContext: $e');
      rethrow;
    }

    return context;
  }

  /// Creates and returns a [SecurityContext] from this stored security context.
  SecurityContext createSecurityContextDem() {
    final context = SecurityContext();

    try {
      // Convert PEM to DER for certificate and private key
      final certDer = _pemToDer(certificate);
      final keyDer = _pemToDer(privateKey);

      // Load the certificate chain from the DER bytes
      context.useCertificateChainBytes(certDer);

      // Load the private key from the DER bytes
      context.usePrivateKeyBytes(keyDer);
    } catch (e) {
      print('Error setting up SecurityContext: $e');
      rethrow;
    }

    return context;
  }

  /// Helper method to convert PEM string to DER bytes
  Uint8List _pemToDer(String pem) {
    final lines = pem
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((line) => line.isNotEmpty && !line.startsWith('---'))
        .join();
    return base64Decode(lines);
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
      'O': '',
      'OU': '',
      'L': '',
      'S': '',
      'C': '',
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
