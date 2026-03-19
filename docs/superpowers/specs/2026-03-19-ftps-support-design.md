# FTPS Support Design Spec

## Overview

Add FTPS (FTP over TLS/SSL) support per RFC 4217 and RFC 2228. Three security modes: plain FTP (existing), explicit FTPS (AUTH TLS upgrade), and implicit FTPS (TLS from connection start).

## Standards

- **RFC 4217** — Securing FTP with TLS (primary)
- **RFC 2228** — FTP Security Extensions (AUTH/PBSZ/PROT/CCC framework)
- **RFC 959** — Base FTP (existing)

## Security Modes

`FtpSecurityMode` enum with three values:

- **`none`** — Plain FTP. Current behavior. No TLS. AUTH command returns 504.
- **`explicit`** — Server listens on plain TCP. Client upgrades via `AUTH TLS`. Control socket upgraded in-place from `Socket` to `SecureSocket`. Data connections encrypted after `PROT P`.
- **`implicit`** — Server listens via `SecureServerSocket`. TLS from connection start. No AUTH needed. Client still sends PBSZ/PROT for data channel configuration.

One mode per server instance. Users who need multiple modes create separate instances.

## TLS Configuration

New `TlsConfig` class:

```dart
class TlsConfig {
  /// Path to PEM certificate file.
  final String? certFilePath;

  /// Path to PEM private key file.
  final String? keyFilePath;

  /// Pre-built SecurityContext for advanced use (custom trust stores, etc.).
  /// When provided, certFilePath/keyFilePath are ignored.
  final SecurityContext? securityContext;

  /// Whether to require client certificates (mutual TLS).
  final bool requireClientCert;
}
```

Validation: either `certFilePath` + `keyFilePath` must be set, or `securityContext` must be provided. Throw `ArgumentError` on construction if neither.

## New FTP Commands

### AUTH (RFC 4217 §4, RFC 2228)

**Syntax:** `AUTH TLS` or `AUTH TLS-C`

**Behavior:**
1. If security mode is `none`: return `504 Security mechanism not understood`.
2. If security mode is `implicit`: return `504 AUTH not needed on implicit TLS connection`.
3. If TLS already active on this session: return `503 TLS already active`.
4. Accept `TLS` and `TLS-C` (case-insensitive). Any other mechanism: return `504`.
5. Send `234 Proceed with TLS negotiation`.
6. Upgrade control socket: `SecureSocket.secure(controlSocket, context: securityContext)`.
7. Replace the control socket listener with the new SecureSocket.
8. Reset all transfer parameters per RFC 4217 §4:
   - `isAuthenticated = false`
   - `cachedUsername = null`
   - `pendingRenameFrom = null`
   - `epsvAllMode = false`
   - Reset CWD to root
   - (Same as `reinitialize()` except TLS stays active)
9. Set `tlsActive = true`.

**Reply codes:**
- 234: AUTH accepted, proceed with TLS
- 504: Mechanism not understood (plain mode, or unknown mechanism)
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
   - If `requireEncryptedData` is irrelevant here (P is always accepted).
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

**Behavior:** Return `500 CCC not supported` (Dart cannot unwrap TLS from a socket).

**Reply codes:**
- 500: Not supported

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

Dart's `SecureSocket` cannot be unwrapped. RFC 4217 §11 requires clearing TLS state on REIN, which is impossible without closing the connection.

### LIST/NLST/RETR/STOR/MLSD (data transfer commands)

Before opening data connection, check:
1. If `requireEncryptedData == true` and `protectionLevel != private`: return `521 Data connection cannot be opened with current PROT setting`.
2. Otherwise proceed normally.

## Data Connection Encryption

### PASV/EPSV (passive mode)

When `protectionLevel == private`:
- Bind with `SecureServerSocket.bind()` instead of `ServerSocket.bind()`.
- Use the same `SecurityContext` as the control connection.

When `protectionLevel == clear`:
- Use plain `ServerSocket.bind()` (current behavior).

### PORT (active mode)

When `protectionLevel == private`:
- Connect with `SecureSocket.connect()` instead of `Socket.connect()`.
- Use the same `SecurityContext`.

When `protectionLevel == clear`:
- Use plain `Socket.connect()` (current behavior).

## Session State

New fields on `FtpSession`:

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `tlsActive` | `bool` | `false` | Control connection is TLS-encrypted |
| `pbszReceived` | `bool` | `false` | PBSZ command was sent (gate for PROT) |
| `protectionLevel` | `ProtectionLevel` | `clear` | Data channel protection (`clear` or `private`) |
| `securityContext` | `SecurityContext?` | `null` | For upgrading sockets |
| `requireEncryptedData` | `bool` | `false` | Server policy flag |
| `securityMode` | `FtpSecurityMode` | `none` | Which mode this session operates in |

For implicit mode: `tlsActive` starts as `true`, `pbszReceived` starts as `false`.

`reinitialize()` resets: `pbszReceived`, `protectionLevel` to `clear`, plus existing resets. Does NOT reset `tlsActive` (TLS persists or REIN is refused).

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

### Server Binding

- `none` / `explicit`: `ServerSocket.bind(InternetAddress.anyIPv4, port)`
- `implicit`: `SecureServerSocket.bind(InternetAddress.anyIPv4, port, securityContext)`

For implicit mode, the accepted sockets are already `SecureSocket`, so `FtpSession` receives a `SecureSocket` and sets `tlsActive = true` immediately.

## Files Changed

| File | Change |
|------|--------|
| `lib/tls_config.dart` | **New** — `TlsConfig`, `FtpSecurityMode`, `ProtectionLevel` |
| `lib/ftp_server.dart` | Add security mode, TLS config, validation. Use SecureServerSocket for implicit. |
| `lib/ftp_session.dart` | Add TLS state fields. AUTH TLS socket upgrade. SecureSocket for data connections when PROT P. Data transfer PROT check. |
| `lib/ftp_command_handler.dart` | Add AUTH, PBSZ, PROT, CCC handlers. Update FEAT. Block REIN when TLS active. |
| `test/ftps_test.dart` | **New** — all FTPS tests with self-signed certs |

## Test Plan

### Unit tests (raw socket, no FTP client needed)

1. **AUTH TLS on explicit server**: returns 234, TLS negotiation succeeds
2. **AUTH TLS-C accepted**: returns 234
3. **AUTH on plain server**: returns 504
4. **AUTH on implicit server**: returns 504
5. **AUTH when TLS already active**: returns 503
6. **AUTH with unknown mechanism**: returns 504
7. **AUTH resets transfer params**: after AUTH, PWD returns root, isAuthenticated false
8. **PBSZ 0 after AUTH**: returns 200
9. **PBSZ before AUTH**: returns 503
10. **PBSZ with non-zero**: returns 501
11. **PROT P after PBSZ**: returns 200
12. **PROT C after PBSZ**: returns 200 (when requireEncryptedData false)
13. **PROT C denied by policy**: returns 534 (when requireEncryptedData true)
14. **PROT before PBSZ**: returns 503
15. **PROT S / PROT E**: returns 504
16. **CCC**: returns 500
17. **REIN when TLS active**: returns 502
18. **FEAT includes AUTH TLS, PBSZ, PROT**: when TLS configured
19. **FEAT unchanged**: when mode is none
20. **Data transfer refused without PROT P**: when requireEncryptedData true, returns 521
21. **Implicit mode**: connection starts with TLS, commands work
22. **Implicit mode**: PBSZ/PROT P, then LIST over encrypted data channel
23. **Explicit mode**: full flow AUTH→PBSZ→PROT P→PASV→LIST
24. **Explicit mode**: data transfer with PROT C (clear data channel)

### Self-signed test certificate

Generate at test setup:
```dart
// Use openssl via Process.run to create test cert/key
Process.run('openssl', ['req', '-x509', '-newkey', 'rsa:2048',
    '-keyout', 'test_key.pem', '-out', 'test_cert.pem',
    '-days', '1', '-nodes', '-subj', '/CN=localhost']);
```

## Error Handling

- TLS handshake failure: log error, close socket, do not crash server.
- Invalid certificate files: throw on `FtpServer` construction (fail fast).
- Client disconnects during TLS upgrade: catch in AUTH handler, log, clean up session.
- Data connection TLS failure: send 426, close data socket, log error.

## Backward Compatibility

- Default `securityMode` is `none`. Existing code works unchanged.
- No new required parameters.
- `requireEncryptedData` defaults to `false`.
- All existing tests continue to pass (they use plain FTP).
