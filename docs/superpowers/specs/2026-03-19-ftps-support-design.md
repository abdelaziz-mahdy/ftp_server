# FTPS Support Design Spec

## Overview

Add FTPS (FTP over TLS/SSL) support per RFC 4217 and RFC 2228. Three security modes: plain FTP (existing), explicit FTPS (AUTH TLS upgrade), and implicit FTPS (TLS from connection start).

## Standards

- **RFC 4217** — Securing FTP with TLS (primary)
- **RFC 2228** — FTP Security Extensions (AUTH/PBSZ/PROT/CCC framework)
- **RFC 959** — Base FTP (existing)

## Known Deviations

- **CCC**: Returns `534` (policy refusal). Dart's `SecureSocket` cannot be unwrapped to plain TCP. RFC 4217 §6 allows servers to refuse CCC.
- **REIN under TLS**: Returns `502`. RFC 4217 §11 requires clearing TLS on REIN, which is impossible with Dart's socket API. Documented as a platform limitation.

## Security Modes

`FtpSecurityMode` enum with three values:

- **`none`** — Plain FTP. Current behavior. No TLS. AUTH command returns 504.
- **`explicit`** — Server listens on plain TCP. Client upgrades via `AUTH TLS`. Control socket upgraded in-place from `Socket` to `SecureSocket`. Data connections encrypted after `PROT P`.
- **`implicit`** — Server listens via `SecureServerSocket`. TLS from connection start. No AUTH needed. Client still sends PBSZ/PROT for data channel configuration. Default session state: `tlsActive = true`, `pbszReceived = true`, `protectionLevel = private`.

One mode per server instance. Users who need multiple modes create separate instances.

For implicit mode, `requireEncryptedData` defaults to `true` at the server level to match the TLS-everywhere intent.

## TLS Configuration

New `TlsConfig` class:

```dart
class TlsConfig {
  /// Path to PEM certificate file.
  final String? certFilePath;

  /// Path to PEM private key file.
  final String? keyFilePath;

  /// Path to PEM trusted CA certificates for client cert validation.
  /// Required when requireClientCert is true and securityContext is null.
  final String? trustedCertificatesPath;

  /// Pre-built SecurityContext for advanced use (custom trust stores, etc.).
  /// When provided, certFilePath/keyFilePath/trustedCertificatesPath are ignored.
  final SecurityContext? securityContext;

  /// Whether to require client certificates (mutual TLS).
  final bool requireClientCert;
}
```

Validation on construction:
- Either `certFilePath` + `keyFilePath` must be set, or `securityContext` must be provided. Throw `ArgumentError` if neither.
- If `requireClientCert == true` and `securityContext == null` and `trustedCertificatesPath == null`: throw `ArgumentError`.

`TlsConfig` builds a `SecurityContext` internally:
```dart
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
```

## New FTP Commands

### AUTH (RFC 4217 §4, RFC 2228)

**Syntax:** `AUTH TLS` or `AUTH TLS-C`

**Pre-auth:** `AUTH`, `PBSZ`, `PROT`, `CCC` are added to `_preAuthCommands` so they work before login.

**Behavior:**
1. If security mode is `none`: return `504 Security mechanism not understood`.
2. If security mode is `implicit`: return `504 AUTH not needed on implicit TLS connection`.
3. If TLS already active on this session: return `503 TLS already active`.
4. Accept `TLS` and `TLS-C` (case-insensitive). Any other mechanism: return `504`.
5. Send `234 Proceed with TLS negotiation`.
6. Upgrade control socket: `SecureSocket.secureServer(controlSocket, securityContext)` (server-side TLS upgrade).
7. Replace `_controlSocket` (mutable field) with the new `SecureSocket`. Re-attach command listener and update `sendResponse` target.
8. Reset all transfer parameters per RFC 4217 §4: call `reinitialize()` which closes data connections, resets auth/CWD/pending state. Then re-set `tlsActive = true` (reinitialize would clear it).
9. Set `tlsActive = true`.

**Reply codes:**
- 234: AUTH accepted, proceed with TLS
- 504: Mechanism not understood (plain mode, implicit mode, or unknown mechanism)
- 503: TLS already active

### PBSZ (RFC 4217 §8)

**Syntax:** `PBSZ 0`

**Behavior:**
1. If TLS not active: return `503 AUTH TLS required first`.
2. Accept argument `0`. Any non-zero or non-numeric: return `501 PBSZ must be 0 for TLS`.
3. Set `pbszReceived = true`.
4. Return `200 PBSZ 0 OK`.

**Reply codes:**
- 200: Accepted
- 503: TLS not negotiated
- 501: Bad syntax

### PROT (RFC 4217 §9)

**Syntax:** `PROT P` or `PROT C`

**Behavior:**
1. If TLS not active: return `503 AUTH TLS required first`.
2. If PBSZ not received: return `503 PBSZ required before PROT`.
3. If argument is `P`:
   - Set `protectionLevel = ProtectionLevel.private`.
   - Return `200 Data protection set to Private`.
4. If argument is `C`:
   - If `requireEncryptedData == true`: return `534 PROT C denied by server policy`.
   - Set `protectionLevel = ProtectionLevel.clear`.
   - Return `200 Data protection set to Clear`.
5. If argument is `S` or `E`: return `504 Protection level not supported`.
6. Empty argument: return `501 Syntax error`.

**Reply codes:**
- 200: Accepted
- 503: Sequence error (no TLS or no PBSZ)
- 504: Level not supported (S, E)
- 534: Policy rejection (PROT C when requireEncryptedData)
- 501: Bad syntax

### CCC (RFC 4217 §6)

**Behavior:** Return `534 CCC denied by server policy` (Dart cannot unwrap TLS from a socket). This is a deliberate deviation — RFC 4217 §6 permits servers to refuse CCC with 534.

**Reply codes:**
- 534: Policy refusal

## Modified Commands

### FEAT

When TLS is configured (mode != none), add to FEAT response:
```
 AUTH TLS
 PBSZ
 PROT
```

### REIN

When TLS is active (`tlsActive == true`): return `502 REIN not available when TLS is active`.

**Deliberate deviation from RFC 4217 §11:** The RFC requires clearing TLS state on REIN. Dart's `SecureSocket` cannot be downgraded to a plain `Socket`. Documented in code comments.

### LIST/NLST/RETR/STOR/MLSD (data transfer commands)

Before opening data connection, check:
1. If `requireEncryptedData == true` and `protectionLevel != private`: return `521 Data connection cannot be opened with current PROT setting`.
2. Otherwise proceed normally.

## Data Connection Encryption

### PASV/EPSV (passive mode)

When `protectionLevel == private`:
- Bind with `SecureServerSocket.bind(addr, 0, securityContext)` instead of `ServerSocket.bind()`.
- Use the same `SecurityContext` as the control connection (RFC 4217 §13: SHOULD use same cert).

When `protectionLevel == clear`:
- Use plain `ServerSocket.bind()` (current behavior).

### PORT (active mode)

When `protectionLevel == private`:
- Connect with `SecureSocket.connect(ip, port, context: securityContext)` instead of `Socket.connect()`.

When `protectionLevel == clear`:
- Use plain `Socket.connect()` (current behavior).

### Data connection TLS failure

If TLS negotiation fails on the data connection: send `522 TLS negotiation failed on data connection`, close data socket, log error. (RFC 4217 §10)

## Session State

### Socket mutability

`controlSocket` becomes a **mutable** field (`Socket _controlSocket` with getter) so it can be replaced after AUTH TLS upgrade. `sendResponse` writes to `_controlSocket`. The command listener is re-attached to the new socket after upgrade.

### New fields on `FtpSession`

| Field | Type | Default (none/explicit) | Default (implicit) | Purpose |
|-------|------|------------------------|-------------------|---------|
| `tlsActive` | `bool` | `false` | `true` | Control connection is TLS-encrypted |
| `pbszReceived` | `bool` | `false` | `true` | PBSZ was sent (gate for PROT) |
| `protectionLevel` | `ProtectionLevel` | `clear` | `private` | Data channel protection |
| `securityContext` | `SecurityContext?` | from config | from config | For upgrading sockets |
| `requireEncryptedData` | `bool` | from config | `true` | Server policy flag |
| `securityMode` | `FtpSecurityMode` | from config | from config | Session's security mode |

### `reinitialize()` updates

Resets: `pbszReceived = false`, `protectionLevel = clear`, plus all existing resets (auth, CWD, data connections, pending state). Does NOT reset `tlsActive`, `securityContext`, `securityMode`, `requireEncryptedData`.

## API Changes

### FtpServer Constructor

```dart
FtpServer(
  this.port,
  {this.username,
   this.password,
   required this.fileOperations,
   required this.serverType,
   this.securityMode = FtpSecurityMode.none,
   this.tlsConfig,
   this.requireEncryptedData = false,
   Function(String)? logFunction}
)
```

Validation in constructor:
- If `securityMode != none` and `tlsConfig == null`: throw `ArgumentError`.
- If `securityMode == none` and `tlsConfig != null`: log warning, ignore config.
- For implicit mode: `requireEncryptedData` forced to `true` regardless of parameter.

### Server Binding

- `none` / `explicit`: `ServerSocket.bind(InternetAddress.anyIPv4, port)`
- `implicit`: `SecureServerSocket.bind(InternetAddress.anyIPv4, port, securityContext)`

For implicit mode, accepted sockets are already `SecureSocket` (subtype of `Socket`), so `FtpSession` receives them transparently.

## Files Changed

| File | Change |
|------|--------|
| `lib/tls_config.dart` | **New** — `TlsConfig`, `FtpSecurityMode`, `ProtectionLevel`, `buildContext()` |
| `lib/ftp_server.dart` | Add `securityMode`, `tlsConfig`, `requireEncryptedData`. Validation. `SecureServerSocket` for implicit. Pass TLS config to sessions. |
| `lib/ftp_session.dart` | Make `controlSocket` mutable. Add TLS state fields. AUTH TLS socket upgrade via `SecureSocket.secureServer()`. Secure data connections when PROT P. Data transfer PROT check. Update `reinitialize()`. |
| `lib/ftp_command_handler.dart` | Add `AUTH`, `PBSZ`, `PROT`, `CCC` to `_preAuthCommands`. Add handlers. Update FEAT. Block REIN when TLS active. |
| `test/ftps_test.dart` | **New** — all FTPS tests with committed self-signed test certs |
| `test/test_certs/` | **New** — committed test `cert.pem` and `key.pem` for CI reliability |

## Test Plan

### Command-level tests (raw socket)

1. AUTH TLS on explicit server → 234, TLS negotiation succeeds
2. AUTH TLS-C accepted → 234
3. AUTH on plain server → 504
4. AUTH on implicit server → 504
5. AUTH when TLS already active → 503
6. AUTH with unknown mechanism (e.g. AUTH GSSAPI) → 504
7. AUTH resets transfer params → after AUTH, CWD is root, isAuthenticated false
8. PBSZ 0 after AUTH → 200
9. PBSZ before AUTH → 503
10. PBSZ with non-zero → 501
11. PROT P after PBSZ → 200
12. PROT C after PBSZ → 200 (when requireEncryptedData false)
13. PROT C denied by policy → 534 (when requireEncryptedData true)
14. PROT before PBSZ → 503
15. PROT S / PROT E → 504
16. CCC → 534
17. REIN when TLS active → 502
18. FEAT includes AUTH TLS, PBSZ, PROT when TLS configured
19. FEAT unchanged when mode is none
20. Data transfer refused without PROT P → 521 (when requireEncryptedData true)

### Integration tests

21. Implicit mode: connection starts with TLS, USER/PASS/PWD work
22. Implicit mode: PBSZ/PROT P, then LIST over encrypted data channel
23. Explicit mode: full flow AUTH→PBSZ→PROT P→PASV→LIST
24. Explicit mode: data transfer with PROT C (clear data channel)
25. TLS handshake failure on AUTH: session cleaned up, server stays alive
26. Data connection TLS failure: returns 522
27. ABOR during encrypted data transfer: transfer aborted cleanly
28. requireEncryptedData=true + implicit: PROT P enforced before data
29. Two concurrent sessions: one TLS, one plain (on explicit server)

### Test certificates

Committed PEM files in `test/test_certs/` (generated once, checked in). No runtime openssl dependency. Cert validity: 10 years to avoid CI expiry issues.

## Error Handling

- TLS handshake failure on AUTH: catch exception, log, close session. Server continues.
- Invalid certificate files: throw on `TlsConfig.buildContext()` / `FtpServer` construction (fail fast).
- Client disconnects during TLS upgrade: catch in AUTH handler, log, clean up session.
- Data connection TLS failure: send `522 TLS negotiation failed`, close data socket, log error.
- `SecureServerSocket.bind` failure (implicit mode): throw on `start()`/`startInBackground()`.

## Backward Compatibility

- Default `securityMode` is `none`. Existing code works unchanged.
- No new required parameters.
- `requireEncryptedData` defaults to `false` (except implicit mode where it's forced `true`).
- `controlSocket` changes from `final` to mutable — this is an internal change, not public API.
- All existing tests continue to pass (they use plain FTP).
