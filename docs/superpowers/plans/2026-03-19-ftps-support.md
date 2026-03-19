# FTPS Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add FTPS (FTP over TLS/SSL) per RFC 4217 and RFC 2228 with implicit, explicit, and plain modes.

**Architecture:** New `TlsConfig` class holds certificate config and builds `SecurityContext`. `FtpServer` switches between `ServerSocket`/`SecureServerSocket` based on mode. `FtpSession` gets a mutable control socket for AUTH TLS upgrade and TLS-aware data connections. New AUTH/PBSZ/PROT/CCC command handlers in `FTPCommandHandler`.

**Tech Stack:** Dart `dart:io` (`SecureSocket`, `SecureServerSocket`, `SecurityContext`), no new dependencies.

**Spec:** `docs/superpowers/specs/2026-03-19-ftps-support-design.md`

---

### Task 1: Generate test certificates

**Files:**
- Create: `test/test_certs/cert.pem`
- Create: `test/test_certs/key.pem`

- [ ] **Step 1: Generate self-signed cert and key**

```bash
mkdir -p test/test_certs
openssl req -x509 -newkey rsa:2048 \
  -keyout test/test_certs/key.pem \
  -out test/test_certs/cert.pem \
  -days 3650 -nodes \
  -subj '/CN=localhost'
```

- [ ] **Step 2: Verify files exist and are valid**

```bash
openssl x509 -in test/test_certs/cert.pem -noout -subject
# Expected: subject=CN = localhost
openssl rsa -in test/test_certs/key.pem -check -noout
# Expected: RSA key ok
```

- [ ] **Step 3: Commit**

```bash
git add test/test_certs/
git commit -m "Add self-signed test certificates for FTPS tests"
```

---

### Task 2: Create `TlsConfig`, `FtpSecurityMode`, `ProtectionLevel`

**Files:**
- Create: `lib/tls_config.dart`
- Test: `test/tls_config_test.dart`

- [ ] **Step 1: Write failing tests for TlsConfig validation**

```dart
// test/tls_config_test.dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/tls_config_test.dart`
Expected: compilation errors (TlsConfig doesn't exist yet)

- [ ] **Step 3: Implement TlsConfig, FtpSecurityMode, ProtectionLevel**

```dart
// lib/tls_config.dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dart test test/tls_config_test.dart`
Expected: All pass

- [ ] **Step 5: Run dart analyze**

Run: `dart analyze lib/tls_config.dart`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/tls_config.dart test/tls_config_test.dart
git commit -m "Add TlsConfig, FtpSecurityMode, ProtectionLevel (RFC 4217)"
```

---

### Task 3: Update FtpServer for TLS modes

**Files:**
- Modify: `lib/ftp_server.dart`

- [ ] **Step 1: Add TLS fields and validation to FtpServer**

Add imports and new fields to `FtpServer`:

```dart
import 'package:ftp_server/tls_config.dart';
```

New fields:
```dart
final FtpSecurityMode securityMode;
final TlsConfig? tlsConfig;
final bool requireEncryptedData;
SecurityContext? _securityContext;
```

Update constructor:
```dart
FtpServer(this.port,
    {this.username,
    this.password,
    required this.fileOperations,
    required this.serverType,
    this.securityMode = FtpSecurityMode.none,
    this.tlsConfig,
    bool requireEncryptedData = false,
    Function(String)? logFunction})
    : requireEncryptedData = securityMode == FtpSecurityMode.implicit
          ? true
          : requireEncryptedData,
      logger = LoggerHandler(logFunction) {
  if (securityMode != FtpSecurityMode.none && tlsConfig == null) {
    throw ArgumentError('tlsConfig required when securityMode is not none');
  }
  if (securityMode != FtpSecurityMode.none) {
    _securityContext = tlsConfig!.buildContext();
  }
}
```

- [ ] **Step 2: Update start() and startInBackground() for implicit mode**

For implicit mode, use `SecureServerSocket.bind` instead of `ServerSocket.bind`. The `_server` field type changes to `dynamic` to hold either `ServerSocket` or `SecureServerSocket`, or use a common approach. Since `SecureServerSocket` does NOT extend `ServerSocket`, use a helper method:

```dart
Future<void> start() async {
  if (securityMode == FtpSecurityMode.implicit) {
    final secureServer = await SecureServerSocket.bind(
      InternetAddress.anyIPv4, port, _securityContext!,
      requestClientCertificate: tlsConfig?.requireClientCert ?? false,
    );
    logger.generalLog('FTPS Server (implicit) is running on port $port');
    await for (var socket in secureServer) {
      logger.generalLog(
          'New TLS client connected from ${socket.remoteAddress.address}:${socket.remotePort}');
      _createSession(socket, tlsActive: true);
    }
  } else {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    logger.generalLog('FTP Server is running on port $port');
    await for (var socket in _server!) {
      logger.generalLog(
          'New client connected from ${socket.remoteAddress.address}:${socket.remotePort}');
      _createSession(socket);
    }
  }
}
```

Do the same for `startInBackground()`. Add a `SecureServerSocket? _secureServer` field. Update `stop()` to close whichever server is active.

- [ ] **Step 3: Update _createSession to pass TLS config**

```dart
FtpSession _createSession(Socket socket, {bool tlsActive = false}) {
  late FtpSession session;
  session = FtpSession(
    socket,
    username: username,
    password: password,
    fileOperations: fileOperations,
    serverType: serverType,
    logger: logger,
    securityContext: _securityContext,
    securityMode: securityMode,
    requireEncryptedData: requireEncryptedData,
    tlsActive: tlsActive,
    onDisconnect: () {
      _sessionList.remove(session);
    },
  );
  _sessionList.add(session);
  return session;
}
```

- [ ] **Step 4: Run existing tests to verify no regressions**

Run: `dart test`
Expected: All existing tests pass (they use plain mode defaults)

- [ ] **Step 5: Commit**

```bash
git add lib/ftp_server.dart
git commit -m "Update FtpServer for TLS modes (implicit/explicit/none)"
```

---

### Task 4: Update FtpSession for TLS state and mutable control socket

**Files:**
- Modify: `lib/ftp_session.dart`

- [ ] **Step 1: Make controlSocket mutable, add TLS state fields**

Change `final Socket controlSocket;` to `Socket _controlSocket;` with getter:
```dart
Socket _controlSocket;
Socket get controlSocket => _controlSocket;
```

Add new fields:
```dart
bool tlsActive;
bool pbszReceived;
ProtectionLevel protectionLevel;
final SecurityContext? securityContext;
final bool requireEncryptedData;
final FtpSecurityMode securityMode;
```

Update constructor signature to accept new parameters. For implicit mode, set `tlsActive = true`, `pbszReceived = true`, `protectionLevel = ProtectionLevel.private_`.

- [ ] **Step 2: Update sendResponse to use _controlSocket**

```dart
void sendResponse(String message) {
  logger.logResponse(message);
  try {
    _controlSocket.write('$message\r\n');
  } catch (e) {
    logger.generalLog('Error sending response: $e');
  }
}
```

Update all other direct uses of `controlSocket` to `_controlSocket`.

- [ ] **Step 3: Add upgradeToTls() method for AUTH TLS**

```dart
Future<void> upgradeToTls() async {
  final secureSocket = await SecureSocket.secureServer(
    _controlSocket,
    securityContext!,
    requestClientCertificate: false, // configured separately
  );
  _controlSocket = secureSocket;
  tlsActive = true;
  // Re-attach listeners
  _commandBuffer.clear();
  _pendingCommands.clear();
  _controlSocket.listen(
    processCommand,
    onDone: closeConnection,
    onError: (error) {
      logger.generalLog('Control socket error: $error');
      closeConnection();
    },
  );
}
```

- [ ] **Step 4: Add requireProtected data check helper**

```dart
bool checkDataProtection() {
  if (requireEncryptedData && protectionLevel != ProtectionLevel.private_) {
    sendResponse('521 Data connection cannot be opened with current PROT setting');
    return false;
  }
  return true;
}
```

Call this at the top of `listDirectory`, `listDirectoryNames`, `retrieveFile`, `storeFile`, `handleMlsd` before `openDataConnection()`.

- [ ] **Step 5: Update enterPassiveMode for PROT P**

When `protectionLevel == ProtectionLevel.private_`:
```dart
dataListener = await SecureServerSocket.bind(
  InternetAddress.anyIPv4, 0, securityContext!);
```
Otherwise use the existing `ServerSocket.bind`.

Note: `SecureServerSocket` is not a `ServerSocket`. Need a dynamic field or abstraction. Store as `dynamic` or use a wrapper. The simplest approach: keep `dataListener` as `ServerSocket?` for plain, add `SecureServerSocket? _secureDataListener` for TLS. In `waitForClientDataSocket`, use whichever is non-null.

- [ ] **Step 6: Update enterActiveMode for PROT P**

When `protectionLevel == ProtectionLevel.private_`:
```dart
dataSocket = await SecureSocket.connect(ip, port, context: securityContext!);
```

- [ ] **Step 7: Update enterExtendedPassiveMode same as passive**

Same pattern as `enterPassiveMode`.

- [ ] **Step 8: Update reinitialize() to reset TLS session state**

```dart
void reinitialize() {
  // existing resets...
  pbszReceived = false;
  protectionLevel = ProtectionLevel.clear;
  // Do NOT reset tlsActive, securityContext, securityMode, requireEncryptedData
}
```

- [ ] **Step 9: Run existing tests**

Run: `dart test`
Expected: All existing tests pass

- [ ] **Step 10: Commit**

```bash
git add lib/ftp_session.dart
git commit -m "Add TLS state management to FtpSession (mutable socket, PROT, data encryption)"
```

---

### Task 5: Add AUTH, PBSZ, PROT, CCC command handlers

**Files:**
- Modify: `lib/ftp_command_handler.dart`

- [ ] **Step 1: Add AUTH/PBSZ/PROT/CCC to _preAuthCommands**

```dart
static const _preAuthCommands = {
  'USER', 'PASS', 'QUIT', 'FEAT', 'SYST', 'NOOP', 'OPTS',
  'REIN', 'ACCT', 'AUTH', 'PBSZ', 'PROT', 'CCC',
};
```

- [ ] **Step 2: Add switch cases for new commands**

```dart
case 'AUTH':
  await handleAuth(argument, session);
  break;
case 'PBSZ':
  handlePbsz(argument, session);
  break;
case 'PROT':
  handleProt(argument, session);
  break;
case 'CCC':
  session.sendResponse('534 CCC denied by server policy');
  break;
```

- [ ] **Step 3: Implement handleAuth**

```dart
Future<void> handleAuth(String argument, FtpSession session) async {
  if (session.securityMode == FtpSecurityMode.none) {
    session.sendResponse('504 Security mechanism not understood');
    return;
  }
  if (session.securityMode == FtpSecurityMode.implicit) {
    session.sendResponse('504 AUTH not needed on implicit TLS connection');
    return;
  }
  if (session.tlsActive) {
    session.sendResponse('503 TLS already active');
    return;
  }
  final mech = argument.toUpperCase();
  if (mech != 'TLS' && mech != 'TLS-C') {
    session.sendResponse('504 Security mechanism not understood');
    return;
  }
  session.sendResponse('234 Proceed with TLS negotiation');
  try {
    await session.upgradeToTls();
    // RFC 4217 §4: reset all transfer params after AUTH
    session.reinitialize();
    session.tlsActive = true; // reinitialize clears this, re-set
  } catch (e) {
    logger.generalLog('TLS handshake failed: $e');
    session.closeConnection();
  }
}
```

- [ ] **Step 4: Implement handlePbsz**

```dart
void handlePbsz(String argument, FtpSession session) {
  if (!session.tlsActive) {
    session.sendResponse('503 AUTH TLS required first');
    return;
  }
  if (argument != '0') {
    session.sendResponse('501 PBSZ must be 0 for TLS');
    return;
  }
  session.pbszReceived = true;
  session.sendResponse('200 PBSZ 0 OK');
}
```

- [ ] **Step 5: Implement handleProt**

```dart
void handleProt(String argument, FtpSession session) {
  if (!session.tlsActive) {
    session.sendResponse('503 AUTH TLS required first');
    return;
  }
  if (!session.pbszReceived) {
    session.sendResponse('503 PBSZ required before PROT');
    return;
  }
  if (argument.isEmpty) {
    session.sendResponse('501 Syntax error in parameters');
    return;
  }
  final level = argument.toUpperCase();
  switch (level) {
    case 'P':
      session.protectionLevel = ProtectionLevel.private_;
      session.sendResponse('200 Data protection set to Private');
      break;
    case 'C':
      if (session.requireEncryptedData) {
        session.sendResponse('534 PROT C denied by server policy');
      } else {
        session.protectionLevel = ProtectionLevel.clear;
        session.sendResponse('200 Data protection set to Clear');
      }
      break;
    case 'S':
    case 'E':
      session.sendResponse('504 Protection level not supported');
      break;
    default:
      session.sendResponse('504 Protection level not supported');
      break;
  }
}
```

- [ ] **Step 6: Update handleFeat to include TLS features**

```dart
void handleFeat(FtpSession session) {
  session.sendResponse('211-Features:');
  session.sendResponse(' SIZE');
  session.sendResponse(' MDTM');
  session.sendResponse(' MLSD');
  session.sendResponse(' EPSV');
  session.sendResponse(' UTF8');
  if (session.securityMode != FtpSecurityMode.none) {
    session.sendResponse(' AUTH TLS');
    session.sendResponse(' PBSZ');
    session.sendResponse(' PROT');
  }
  session.sendResponse('211 End');
}
```

- [ ] **Step 7: Update handleRein to refuse under TLS**

```dart
void handleRein(FtpSession session) {
  // RFC 4217 §11 deviation: Dart SecureSocket cannot be downgraded
  if (session.tlsActive) {
    session.sendResponse('502 REIN not available when TLS is active');
    return;
  }
  session.reinitialize();
  session.sendResponse('200 REIN command successful');
}
```

- [ ] **Step 8: Update HELP to include AUTH/PBSZ/PROT/CCC**

```dart
void handleHelp(FtpSession session) {
  session.sendResponse('214-The following commands are supported:');
  session.sendResponse(' USER PASS ACCT QUIT REIN PASV PORT EPSV');
  session.sendResponse(' LIST NLST RETR STOR CWD CDUP MKD RMD DELE');
  session.sendResponse(' PWD TYPE SIZE FEAT OPTS SYST NOOP ABOR');
  session.sendResponse(' MLSD MDTM RNFR RNTO STRU MODE ALLO STAT');
  session.sendResponse(' AUTH PBSZ PROT CCC SITE HELP');
  session.sendResponse('214 End');
}
```

- [ ] **Step 9: Run existing tests**

Run: `dart test`
Expected: All existing tests pass

- [ ] **Step 10: Commit**

```bash
git add lib/ftp_command_handler.dart
git commit -m "Add AUTH, PBSZ, PROT, CCC command handlers (RFC 4217/2228)"
```

---

### Task 6: Write FTPS command-level tests

**Files:**
- Create: `test/ftps_test.dart`

- [ ] **Step 1: Write tests for AUTH on plain server**

Test AUTH TLS returns 504 on a plain (none) mode server. Use existing `FtpTestClient` pattern from `ftp_commands_test.dart`.

- [ ] **Step 2: Write tests for AUTH on explicit server**

Set up an explicit server with test certs. Test:
- AUTH TLS → 234
- AUTH TLS-C → 234
- AUTH GSSAPI → 504
- AUTH when TLS already active → 503
- AUTH resets transfer params (CWD to root, isAuthenticated false)

For the TLS tests, create an `FtpTlsTestClient` that can upgrade its socket:
```dart
class FtpTlsTestClient extends FtpTestClient {
  Future<void> upgradeTls() async {
    await _sub.cancel();
    final secureSocket = await SecureSocket.secure(
      _socket,
      context: SecurityContext()..setTrustedCertificates('test/test_certs/cert.pem'),
      onBadCertificate: (_) => true, // Accept self-signed for tests
    );
    // Re-attach listener on secure socket
    ...
  }
}
```

- [ ] **Step 3: Write tests for PBSZ**

- PBSZ 0 after AUTH → 200
- PBSZ before AUTH → 503
- PBSZ with non-zero → 501

- [ ] **Step 4: Write tests for PROT**

- PROT P after PBSZ → 200
- PROT C after PBSZ → 200 (requireEncryptedData=false)
- PROT C denied → 534 (requireEncryptedData=true)
- PROT before PBSZ → 503
- PROT S → 504
- PROT E → 504

- [ ] **Step 5: Write tests for CCC**

- CCC → 534

- [ ] **Step 6: Write tests for REIN under TLS**

- REIN when TLS active → 502

- [ ] **Step 7: Write tests for FEAT with TLS**

- FEAT includes AUTH TLS, PBSZ, PROT when TLS configured
- FEAT does not include them when mode is none

- [ ] **Step 8: Write test for data protection enforcement**

- LIST when requireEncryptedData=true and PROT C → 521

- [ ] **Step 9: Run all tests**

Run: `dart test`
Expected: All pass

- [ ] **Step 10: Commit**

```bash
git add test/ftps_test.dart
git commit -m "Add comprehensive FTPS command-level tests (RFC 4217)"
```

---

### Task 7: Write FTPS integration tests

**Files:**
- Modify: `test/ftps_test.dart`

- [ ] **Step 1: Implicit mode integration test**

Connect via `SecureSocket.connect` to implicit server. Verify 220 welcome, USER/PASS, PWD all work over TLS.

- [ ] **Step 2: Implicit mode data transfer test**

PBSZ 0, PROT P, then PASV + LIST over encrypted data channel. Verify 226 received.

- [ ] **Step 3: Explicit mode full flow test**

Plain connect → AUTH TLS → TLS upgrade → USER/PASS → PBSZ 0 → PROT P → PASV → LIST. Verify full encrypted flow.

- [ ] **Step 4: Explicit mode clear data channel test**

AUTH TLS → PBSZ 0 → PROT C → PASV → LIST over plain data channel.

- [ ] **Step 5: TLS handshake failure test**

Send AUTH TLS but close the socket before TLS negotiation completes. Verify server stays alive and accepts new connections.

- [ ] **Step 6: Concurrent sessions test**

On explicit server: one session upgrades to TLS, another stays plain. Both work independently.

- [ ] **Step 7: Run all tests**

Run: `dart test`
Expected: All pass

- [ ] **Step 8: Commit**

```bash
git add test/ftps_test.dart
git commit -m "Add FTPS integration tests (implicit, explicit, concurrent)"
```

---

### Task 8: Update exports, CHANGELOG, README, final verification

**Files:**
- Modify: `lib/ftp_server.dart` (export TlsConfig)
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Export TlsConfig from package**

Ensure `TlsConfig`, `FtpSecurityMode`, `ProtectionLevel` are importable by users. Add an export in `lib/ftp_server.dart` or create a barrel file.

- [ ] **Step 2: Update CHANGELOG for FTPS**

Add under 2.2.0 or bump to 2.3.0 if merited:
```
### FTPS Support (RFC 4217 / RFC 2228)
- Explicit FTPS: AUTH TLS/TLS-C upgrade on standard port
- Implicit FTPS: TLS from connection start (SecureServerSocket)
- Data channel encryption via PROT P/C with configurable enforcement
- New commands: AUTH, PBSZ, PROT, CCC
- TlsConfig class for certificate configuration (PEM files or SecurityContext)
- Mutual TLS (client certificate) support
- FEAT advertises AUTH TLS, PBSZ, PROT when TLS configured
```

- [ ] **Step 3: Update README**

Add RFC 4217 and RFC 2228 to the standards list. Add FTPS usage example. Add AUTH/PBSZ/PROT/CCC to command table.

- [ ] **Step 4: Run full test suite + analyze + format**

```bash
dart analyze
dart format --set-exit-if-changed lib/ test/
dart test
```

Expected: All clean, all pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Update exports, changelog, readme for FTPS support"
```

---

### Task 9: Push, PR, CI, merge

- [ ] **Step 1: Push branch**

```bash
git push -u origin ftps-support
```

- [ ] **Step 2: Create PR**

```bash
gh pr create --title "Add FTPS support (RFC 4217/2228)" --body "..."
```

- [ ] **Step 3: Watch CI**

```bash
gh run watch <run-id> --exit-status
```

- [ ] **Step 4: Fix any CI failures**

- [ ] **Step 5: Merge when green**

```bash
gh pr merge <number> --squash
```
