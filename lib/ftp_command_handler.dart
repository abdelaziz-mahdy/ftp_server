import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/socket_wrapper/plain_socket_wrapper.dart';
import 'logger_handler.dart';

class FTPCommandHandler {
  final LoggerHandler logger;

  FTPCommandHandler(this.logger);

  Future<void> handleCommand(String commandLine, FtpSession session) async {
    List<String> parts = commandLine.split(' ');
    String command = parts[0].toUpperCase();
    String argument =
        parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';

    logger.logCommand(command, argument);

    switch (command) {
      case 'USER':
        handleUser(argument, session);
        break;
      case 'PASS':
        handlePass(argument, session);
        break;
      case 'QUIT':
        handleQuit(session);
        break;
      case 'PASV':
        handlePasv(session);
        break;
      case 'PORT':
        handlePort(argument, session);
        break;
      case 'LIST':
      case 'NLST':
        handleList(argument, session);
        break;
      case 'RETR':
        handleRetr(argument, session);
        break;
      case 'STOR':
        handleStor(argument, session);
        break;
      case 'CWD':
        handleCwd(argument, session);
        break;
      case 'CDUP':
        handleCdup(session);
        break;
      case 'MKD':
      case 'XMKD':
        handleMkd(argument, session);
        break;
      case 'RMD':
      case 'XRMD':
        handleRmd(argument, session);
        break;
      case 'DELE':
        handleDele(argument, session);
        break;
      case 'SYST':
        handleSyst(session);
        break;
      case 'NOOP':
        handleNoop(session);
        break;
      case 'TYPE':
        handleType(argument, session);
        break;
      case 'SIZE':
        handleSize(argument, session);
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
        handleEpsv(session);
        break;
      case 'ABOR':
        handleAbort(session);
        break;
      case 'MLSD':
        handleMlsd(argument, session);
        break;
      case 'MDTM':
        handleMdtm(argument, session);
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
      case 'RNFR':
        handleRnfr(argument, session);
        break;
      case 'RNTO':
        handleRnto(argument, session);
        break;
      case 'RENAME':
        handleRename(argument, session);
        break;
      default:
        session.sendResponse('502 Command not implemented $command $argument');
        break;
    }
  }

  void handleUser(String argument, FtpSession session) {
    session.cachedUsername = argument;
    session.isAuthenticated = false;
    session.sendResponse('331 Password required for $argument');
  }

  void handlePass(String argument, FtpSession session) {
    if ((session.username == null && session.password == null) ||
        (session.cachedUsername == session.username &&
            argument == session.password)) {
      session.isAuthenticated = true;
      session.sendResponse('230 User logged in, proceed');
    } else {
      session.sendResponse('530 Not logged in');
    }
  }

  Future<void> handleQuit(FtpSession session) async {
    session.sendResponse('221 Service closing control connection');
    await session.controlSocket.close();
  }

  void handlePasv(FtpSession session) {
    session.enterPassiveMode();
  }

  void handlePort(String argument, FtpSession session) {
    session.enterActiveMode(argument);
  }

  void handleList(String argument, FtpSession session) {
    session.listDirectory(argument);
  }

  void handleRetr(String argument, FtpSession session) {
    session.retrieveFile(argument);
  }

  void handleMlsd(String argument, FtpSession session) {
    session.handleMlsd(argument, session);
  }

  void handleMdtm(String argument, FtpSession session) {
    session.handleMdtm(argument, session);
  }

  void handleStor(String argument, FtpSession session) {
    if (session.serverType == ServerType.readOnly) {
      session.sendResponse('550 Command not allowed in read-only mode');
    } else {
      session.storeFile(argument);
    }
  }

  void handleCwd(String argument, FtpSession session) {
    session.changeDirectory(argument);
  }

  void handleCdup(FtpSession session) {
    session.changeToParentDirectory();
  }

  void handleMkd(String argument, FtpSession session) {
    if (session.serverType == ServerType.readOnly) {
      session.sendResponse('550 Command not allowed in read-only mode');
    } else {
      session.makeDirectory(argument);
    }
  }

  void handleRmd(String argument, FtpSession session) {
    if (session.serverType == ServerType.readOnly) {
      session.sendResponse('550 Command not allowed in read-only mode');
    } else {
      session.removeDirectory(argument);
    }
  }

  void handleDele(String argument, FtpSession session) {
    if (session.serverType == ServerType.readOnly) {
      session.sendResponse('550 Command not allowed in read-only mode');
    } else {
      session.deleteFile(argument);
    }
  }

  void handleSyst(FtpSession session) {
    session.sendResponse('215 UNIX Type: L8');
  }

  void handleNoop(FtpSession session) {
    session.sendResponse('200 NOOP command successful');
  }

  void handleType(String argument, FtpSession session) {
    if (argument == 'A' || argument == 'I') {
      session.sendResponse('200 Type set to $argument');
    } else {
      session.sendResponse('500 Syntax error, command unrecognized');
    }
  }

  void handleSize(String argument, FtpSession session) {
    session.fileSize(argument);
  }

  void handleCurPath(FtpSession session) {
    String currentPath = session.fileOperations.getCurrentDirectory();
    session.sendResponse('257 "$currentPath" is current directory');
  }

  void handleOptions(String argument, FtpSession session) {
    var args = argument.split(" ");
    var option = args[0].toUpperCase();
    switch (option) {
      case "UTF8":
        var mode = args[1].toUpperCase() == "ON";
        session.sendResponse("200 UTF8 mode ${mode ? 'enable' : 'disable'}");
        break;
      default:
        session.sendResponse('502 Command not implemented handleOptions');
        break;
    }
  }

  void handleFeat(FtpSession session) {
    session.sendResponse('211-Features:');

    if (session.secureConnectionAllowed || session.enforceSecureConnections) {
      session.sendResponse(' AUTH TLS');
      session.sendResponse(' PBSZ');
      session.sendResponse(' PROT');
    }
    session.sendResponse(' SIZE');
    session.sendResponse(' MDTM');
    session.sendResponse(' EPSV');
    session.sendResponse(' PASV');
    session.sendResponse(' UTF8');
    session.sendResponse('211 End');
  }

  void handleEpsv(FtpSession session) {
    session.enterExtendedPassiveMode();
  }

  void handleAbort(FtpSession session) {
    session.abortTransfer();
  }

  void handlePbsz(String argument, FtpSession session) {
    if (session.secure) {
      if (argument == '0') {
        session.sendResponse('200 PBSZ command successful.');
      } else {
        session.sendResponse('501 Invalid PBSZ argument.');
      }
    } else {
      session.sendResponse('503 Security data exchange not complete.');
    }
  }

  void handleProt(String argument, FtpSession session) {
    if (!session.secure) {
      session.sendResponse('503 Security data exchange not complete.');
      return;
    }

    switch (argument.toUpperCase()) {
      case 'P':
        session.secureDataConnection = true;
        session.sendResponse('200 PROT command successful. Using Private.');
        break;
      case 'C':
        session.secureDataConnection = false;
        session.sendResponse('200 PROT command successful. Using Clear.');
        break;
      default:
        session.sendResponse('504 PROT level not supported.');
    }
  }

  /// Handles AUTH TLS - upgrades the control connection to TLS.
  ///
  /// This is the explicit FTPS flow per RFC 4217:
  /// 1. Send 234 response
  /// 2. Flush the response to ensure client receives it
  /// 3. Cancel old plain socket listener (prevents onDone → closeConnection)
  /// 4. Perform TLS handshake on the underlying socket
  /// 5. Re-subscribe to the new secure socket
  Future<void> handleAuth(String argument, FtpSession session) async {
    if (argument.toUpperCase() != 'TLS') {
      session.sendResponse('504 AUTH type not supported');
      return;
    }

    if (!session.secureConnectionAllowed) {
      session.sendResponse('502 AUTH TLS not enabled on this server');
      return;
    }

    if (session.controlSocket is! PlainSocketWrapper) {
      session.sendResponse('503 Already secured');
      return;
    }

    try {
      // Send 234 BEFORE the upgrade. The upgrade method handles flushing
      // and re-subscribing.
      session.sendResponse('234 AUTH TLS successful');
      await session.upgradeToTls();
    } catch (e) {
      session.logger.generalLog('AUTH TLS failed: $e');
      // Connection is likely broken at this point - can't send a response
      // because the socket state is unknown after a failed TLS handshake.
      session.closeConnection();
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

  void handleRnto(String argument, FtpSession session) {
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

    try {
      session.renameFileOrDirectory(session.pendingRenameFrom!, argument);
    } catch (e) {
      session.pendingRenameFrom = null;
      rethrow;
    }
  }

  void handleRename(String argument, FtpSession session) {
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

    try {
      session.renameFileOrDirectory(oldName, newName);
    } catch (e) {
      // Error handling is done in the session method
    }
  }
}
