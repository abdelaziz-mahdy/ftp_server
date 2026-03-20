import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/tls_config.dart';
import 'logger_handler.dart';

class FTPCommandHandler {
  final LoggerHandler logger;

  FTPCommandHandler(this.logger);

  /// Commands that are allowed before authentication (RFC 959, RFC 4217)
  static const _preAuthCommands = {
    'USER',
    'PASS',
    'QUIT',
    'FEAT',
    'SYST',
    'NOOP',
    'OPTS',
    'REIN',
    'ACCT',
    'AUTH',
    'PBSZ',
    'PROT',
    'CCC',
  };

  Future<void> handleCommand(String commandLine, FtpSession session) async {
    List<String> parts = commandLine.split(' ');
    String command = parts[0].toUpperCase();
    String argument = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';

    logger.logCommand(command, argument);

    // Enforce authentication when credentials are configured
    if (!session.isAuthenticated &&
        !_preAuthCommands.contains(command) &&
        (session.username != null || session.password != null)) {
      session.sendResponse('530 Not logged in');
      return;
    }

    switch (command) {
      case 'USER':
        handleUser(argument, session);
        break;
      case 'PASS':
        handlePass(argument, session);
        break;
      case 'QUIT':
        await handleQuit(session);
        break;
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
      case 'PASV':
        if (session.epsvAllMode) {
          session.sendResponse('503 PASV not allowed after EPSV ALL');
        } else {
          await session.enterPassiveMode();
        }
        break;
      case 'PORT':
        if (session.epsvAllMode) {
          session.sendResponse('503 PORT not allowed after EPSV ALL');
        } else {
          await session.enterActiveMode(argument);
        }
        break;
      case 'LIST':
        await session.listDirectory(_stripListFlags(argument));
        break;
      case 'NLST':
        await session.listDirectoryNames(_stripListFlags(argument));
        break;
      case 'RETR':
        await session.retrieveFile(argument);
        break;
      case 'STOR':
        if (session.serverType == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          await session.storeFile(argument);
        }
        break;
      case 'CWD':
        session.changeDirectory(argument);
        break;
      case 'CDUP':
        session.changeToParentDirectory();
        break;
      case 'MKD':
      case 'XMKD':
        if (session.serverType == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          await session.makeDirectory(argument);
        }
        break;
      case 'RMD':
      case 'XRMD':
        if (session.serverType == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          await session.removeDirectory(argument);
        }
        break;
      case 'DELE':
        if (session.serverType == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          await session.deleteFile(argument);
        }
        break;
      case 'SYST':
        session.sendResponse('215 UNIX Type: L8');
        break;
      case 'NOOP':
        session.sendResponse('200 NOOP command successful');
        break;
      case 'TYPE':
        handleType(argument, session);
        break;
      case 'SIZE':
        await session.fileSize(argument);
        break;
      case 'PWD':
      case 'XPWD':
        handleCurPath(session);
        break;
      case 'OPTS':
        handleOptions(argument, session);
        break;
      case 'FEAT':
        handleFeat(session);
        break;
      case 'EPSV':
        await handleEpsv(argument, session);
        break;
      case 'ABOR':
        session.abortTransfer();
        break;
      case 'MLSD':
        await session.handleMlsd(argument);
        break;
      case 'MDTM':
        session.handleMdtm(argument);
        break;
      case 'RNFR':
        handleRnfr(argument, session);
        break;
      case 'RNTO':
        await handleRnto(argument, session);
        break;
      case 'RENAME':
        await handleRename(argument, session);
        break;
      case 'STRU':
        handleStru(argument, session);
        break;
      case 'MODE':
        handleMode(argument, session);
        break;
      case 'ALLO':
        handleAllo(argument, session);
        break;
      case 'STAT':
        await handleStat(argument, session);
        break;
      case 'HELP':
        handleHelp(session);
        break;
      case 'SITE':
        handleSite(argument, session);
        break;
      case 'ACCT':
        handleAcct(argument, session);
        break;
      case 'REIN':
        handleRein(session);
        break;
      default:
        session.sendResponse('502 Command not implemented');
        break;
    }
  }

  void handleUser(String argument, FtpSession session) {
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    session.cachedUsername = argument;
    session.isAuthenticated = false;
    // No credentials configured — log in directly (RFC 959: 230 on USER)
    if (session.username == null && session.password == null) {
      session.isAuthenticated = true;
      session.sendResponse('230 User logged in, proceed');
    } else {
      session.sendResponse('331 Password required for $argument');
    }
  }

  void handlePass(String argument, FtpSession session) {
    if (session.cachedUsername == null) {
      session.sendResponse('503 Bad sequence of commands');
      return;
    }
    // No credentials configured — accept anyone
    if (session.username == null && session.password == null) {
      session.isAuthenticated = true;
      session.sendResponse('230 User logged in, proceed');
      return;
    }
    // Validate only the non-null credentials
    final userOk =
        session.username == null || session.cachedUsername == session.username;
    final passOk = session.password == null || argument == session.password;
    if (userOk && passOk) {
      session.isAuthenticated = true;
      session.sendResponse('230 User logged in, proceed');
    } else {
      session.sendResponse('530 Not logged in');
    }
  }

  Future<void> handleQuit(FtpSession session) async {
    session.sendResponse('221 Service closing control connection');
    session.closeConnection();
  }

  /// AUTH: Authenticate / negotiate TLS (RFC 4217 §4, RFC 2228).
  Future<void> handleAuth(String argument, FtpSession session) async {
    // Mode none: TLS not supported
    if (session.securityMode == FtpSecurityMode.none) {
      session.sendResponse('504 Security mechanism not understood');
      return;
    }
    // Implicit mode: AUTH not needed (connection is already TLS)
    if (session.securityMode == FtpSecurityMode.implicit) {
      session.sendResponse('504 AUTH not needed on implicit TLS connection');
      return;
    }
    // Already upgraded
    if (session.tlsActive) {
      session.sendResponse('503 TLS already active');
      return;
    }
    // Validate mechanism
    final mechanism = argument.toUpperCase();
    if (mechanism != 'TLS' && mechanism != 'TLS-C') {
      session.sendResponse('504 Security mechanism not understood');
      return;
    }

    session.sendResponse('234 Proceed with TLS negotiation');

    try {
      await session.upgradeToTls();
      // RFC 4217 §4: reset transfer parameters after AUTH
      session.reinitialize();
      session.tlsActive = true;
    } catch (e) {
      logger.generalLog('TLS upgrade failed: $e');
      session.closeConnection();
    }
  }

  /// PBSZ: Protection Buffer Size (RFC 4217 §8).
  /// For TLS, must be 0.
  void handlePbsz(String argument, FtpSession session) {
    if (!session.tlsActive) {
      session.sendResponse('503 AUTH TLS required first');
      return;
    }
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    final value = int.tryParse(argument);
    if (value == null || value != 0) {
      session.sendResponse('501 PBSZ must be 0 for TLS');
      return;
    }
    session.pbszReceived = true;
    session.sendResponse('200 PBSZ 0 OK');
  }

  /// PROT: Data Channel Protection Level (RFC 4217 §9).
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

  /// Strips LIST flags (e.g., -la, -a) that clients like FileZilla send.
  /// Only strips tokens that look like flags (start with '-' and contain
  /// no path separators), preserving valid paths like "-backups".
  String _stripListFlags(String argument) {
    if (argument.isEmpty) return argument;
    final parts = argument.split(' ');
    final filtered = parts
        .where((p) {
          return !(p.startsWith('-') && !p.contains('/') && !p.contains('\\'));
        })
        .join(' ')
        .trim();
    return filtered;
  }

  void handleType(String argument, FtpSession session) {
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    // Handle TYPE A, TYPE I, and TYPE A N (ASCII Non-print) forms
    final type = argument.split(' ').first.toUpperCase();
    if (type == 'A' || type == 'I') {
      session.sendResponse('200 Type set to $type');
    } else {
      session.sendResponse('504 Type not supported');
    }
  }

  void handleCurPath(FtpSession session) {
    String currentPath = session.fileOperations.getCurrentDirectory();
    session.sendResponse('257 "$currentPath" is current directory');
  }

  void handleOptions(String argument, FtpSession session) {
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    var args = argument.split(" ");
    var option = args[0].toUpperCase();
    switch (option) {
      case "UTF8":
        if (args.length < 2) {
          session.sendResponse('501 Syntax error in parameters');
          return;
        }
        var mode = args[1].toUpperCase() == "ON";
        session.sendResponse("200 UTF8 mode ${mode ? 'enable' : 'disable'}");
        break;
      default:
        session.sendResponse('502 Command not implemented');
        break;
    }
  }

  void handleFeat(FtpSession session) {
    // RFC 2389: FEAT only lists extensions not in RFC 959
    // PASV is a base command and must not appear here
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

  Future<void> handleEpsv(String argument, FtpSession session) async {
    if (argument.toUpperCase() == 'ALL') {
      // RFC 2428 §4: after EPSV ALL, server must refuse PORT/PASV/LPRT
      session.epsvAllMode = true;
      session.sendResponse('200 EPSV ALL command successful');
    } else if (argument.isEmpty || argument == '1') {
      // Empty = server chooses; '1' = IPv4
      await session.enterExtendedPassiveMode();
    } else if (argument == '2') {
      // IPv6 not supported
      session.sendResponse('522 Network protocol not supported, use (1)');
    } else {
      session.sendResponse('501 Syntax error in parameters');
    }
  }

  void handleRnfr(String argument, FtpSession session) {
    if (session.serverType == ServerType.readOnly) {
      session.sendResponse('550 Command not allowed in read-only mode');
      return;
    }
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters or arguments');
      return;
    }
    if (!session.fileOperations.exists(argument)) {
      session.sendResponse('550 File not found');
      return;
    }
    session.pendingRenameFrom = argument;
    session
        .sendResponse('350 Requested file action pending further information');
  }

  Future<void> handleRnto(String argument, FtpSession session) async {
    if (session.serverType == ServerType.readOnly) {
      session.sendResponse('550 Command not allowed in read-only mode');
      return;
    }
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters or arguments');
      return;
    }
    if (session.pendingRenameFrom == null) {
      session.sendResponse('503 Bad sequence of commands');
      return;
    }
    await session.renameFileOrDirectory(session.pendingRenameFrom!, argument);
  }

  Future<void> handleRename(String argument, FtpSession session) async {
    if (session.serverType == ServerType.readOnly) {
      session.sendResponse('550 Command not allowed in read-only mode');
      return;
    }
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters or arguments');
      return;
    }
    final parts = argument.split(' ');
    if (parts.length != 2) {
      session.sendResponse('501 Syntax error in parameters or arguments');
      return;
    }
    final oldName = parts[0];
    final newName = parts[1];
    if (!session.fileOperations.exists(oldName)) {
      session.sendResponse('550 File not found');
      return;
    }
    await session.renameFileOrDirectory(oldName, newName);
  }

  void handleStru(String argument, FtpSession session) {
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    if (argument.toUpperCase() == 'F') {
      session.sendResponse('200 Structure set to File');
    } else {
      session.sendResponse('504 Structure not supported');
    }
  }

  void handleMode(String argument, FtpSession session) {
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    if (argument.toUpperCase() == 'S') {
      session.sendResponse('200 Mode set to Stream');
    } else {
      session.sendResponse('504 Mode not supported');
    }
  }

  /// ALLO: Reserve storage space (RFC 959).
  /// This server does not require pre-allocation, so the command is accepted
  /// as a no-op. The argument (byte count) is validated for correct syntax.
  /// Optional second argument form: `ALLO <bytes> R <record-size>`
  void handleAllo(String argument, FtpSession session) {
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    // Parse: <decimal-bytes> [SP R SP <decimal-record-size>]
    final parts = argument.split(RegExp(r'\s+'));
    final bytes = int.tryParse(parts[0]);
    if (bytes == null || bytes < 0) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    if (parts.length > 1) {
      if (parts.length != 3 ||
          parts[1].toUpperCase() != 'R' ||
          int.tryParse(parts[2]) == null) {
        session.sendResponse('501 Syntax error in parameters');
        return;
      }
    }
    session.sendResponse('200 ALLO command OK (no storage allocation needed)');
  }

  /// ACCT: Provide account information (RFC 959).
  /// This server does not use accounts, so the command is accepted as
  /// superfluous. The argument is validated for non-empty syntax.
  void handleAcct(String argument, FtpSession session) {
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    // This server does not require account information
    session.sendResponse('202 ACCT command superfluous');
  }

  /// REIN: Reinitialize session (RFC 959).
  /// Flushes all user/account information and transfer parameters.
  /// Any transfer in progress is allowed to complete.
  /// The control connection remains open for a new USER command.
  ///
  /// Deliberate deviation from RFC 4217 §11: when TLS is active, REIN
  /// returns 502 because Dart's SecureSocket cannot be downgraded to
  /// a plain Socket.
  void handleRein(FtpSession session) {
    if (session.tlsActive) {
      session.sendResponse('502 REIN not available when TLS is active');
      return;
    }
    session.reinitialize();
    session.sendResponse('200 REIN command successful');
  }

  /// SITE: Execute site-specific commands (RFC 959).
  /// This server does not implement any site-specific commands.
  void handleSite(String argument, FtpSession session) {
    if (argument.isEmpty) {
      session.sendResponse('501 Syntax error in parameters');
      return;
    }
    // No site-specific commands are implemented
    session.sendResponse('502 SITE command not implemented');
  }

  /// STAT: Return server status or file/directory info (RFC 959 §4.1.3).
  /// Without arguments: returns general server status (211).
  /// With a pathname: returns a directory listing over the control connection.
  Future<void> handleStat(String argument, FtpSession session) async {
    if (argument.isEmpty) {
      session.sendResponse('211 Server is running');
      return;
    }
    await session.statPath(argument);
  }

  void handleHelp(FtpSession session) {
    session.sendResponse('214-The following commands are supported:');
    session.sendResponse(' USER PASS ACCT QUIT REIN PASV PORT EPSV');
    session.sendResponse(' LIST NLST RETR STOR CWD CDUP MKD RMD DELE');
    session.sendResponse(' PWD TYPE SIZE FEAT OPTS SYST NOOP ABOR');
    session.sendResponse(' MLSD MDTM RNFR RNTO STRU MODE ALLO STAT');
    session.sendResponse(' AUTH PBSZ PROT CCC SITE HELP');
    session.sendResponse('214 End');
  }
}
