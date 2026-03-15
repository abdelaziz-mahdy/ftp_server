import 'dart:io';
import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'logger_handler.dart';

class FTPCommandHandler {
  final Socket controlSocket;
  final LoggerHandler logger;

  FTPCommandHandler(this.controlSocket, this.logger);

  /// Commands that are allowed before authentication
  static const _preAuthCommands = {
    'USER', 'PASS', 'QUIT', 'FEAT', 'SYST', 'NOOP',
  };

  void handleCommand(String commandLine, FtpSession session) {
    List<String> parts = commandLine.split(' ');
    String command = parts[0].toUpperCase();
    String argument =
        parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';

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
        handleQuit(session);
        break;
      case 'PASV':
        handlePasv(session);
        break;
      case 'PORT':
        handlePort(argument, session);
        break;
      case 'LIST':
        handleList(argument, session);
        break;
      case 'NLST':
        handleNlst(argument, session);
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
        handleEpsv(argument, session);
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
      case 'RNFR':
        handleRnfr(argument, session);
        break;
      case 'RNTO':
        handleRnto(argument, session);
        break;
      case 'RENAME':
        handleRename(argument, session);
        break;
      case 'STRU':
        handleStru(argument, session);
        break;
      case 'MODE':
        handleMode(argument, session);
        break;
      case 'ALLO':
        session.sendResponse('202 ALLO command not needed');
        break;
      default:
        session.sendResponse('502 Command not implemented');
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

  /// Strips LIST flags (e.g., -la, -a) that clients like FileZilla send.
  /// Returns the path portion of the argument.
  String _stripListFlags(String argument) {
    if (argument.isEmpty) return argument;
    final parts = argument.split(' ');
    final filtered = parts.where((p) => !p.startsWith('-')).join(' ').trim();
    return filtered;
  }

  void handleList(String argument, FtpSession session) {
    session.listDirectory(_stripListFlags(argument));
  }

  void handleNlst(String argument, FtpSession session) {
    session.listDirectoryNames(_stripListFlags(argument));
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
    // Handle TYPE A, TYPE I, and TYPE A N (ASCII Non-print) forms
    final type = argument.split(' ').first.toUpperCase();
    if (type == 'A' || type == 'I') {
      session.sendResponse('200 Type set to $type');
    } else {
      session.sendResponse('504 Type not supported');
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
    session.sendResponse('211-Features:');

    session.sendResponse(' SIZE');
    session.sendResponse(' MDTM');
    session.sendResponse(' MLSD');
    session.sendResponse(' EPSV');
    session.sendResponse(' PASV');
    session.sendResponse(' UTF8');
    session.sendResponse('211 End');
  }

  void handleEpsv(String argument, FtpSession session) {
    if (argument.toUpperCase() == 'ALL') {
      // EPSV ALL tells the server the client will only use EPSV from now on
      session.sendResponse('200 EPSV ALL command successful');
    } else {
      session.enterExtendedPassiveMode();
    }
  }

  void handleAbort(FtpSession session) {
    session.abortTransfer();
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

    // Check if the file/directory exists
    if (!session.fileOperations.exists(argument)) {
      session.sendResponse('550 File not found');
      return;
    }

    // Store the source path for the rename operation
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

    // Check if RNFR was called first
    if (session.pendingRenameFrom == null) {
      session.sendResponse('503 Bad sequence of commands');
      return;
    }

    try {
      // Perform the rename operation
      session.renameFileOrDirectory(session.pendingRenameFrom!, argument);
    } catch (e) {
      // Clear the pending rename state on error
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

    // Parse the rename command arguments (oldname newname)
    final parts = argument.split(' ');
    if (parts.length != 2) {
      session.sendResponse('501 Syntax error in parameters or arguments');
      return;
    }

    final oldName = parts[0];
    final newName = parts[1];

    // Check if the file/directory exists
    if (!session.fileOperations.exists(oldName)) {
      session.sendResponse('550 File not found');
      return;
    }

    try {
      // Perform the rename operation directly
      session.renameFileOrDirectory(oldName, newName);
    } catch (e) {
      // Error handling is done in the session method
    }
  }

  void handleStru(String argument, FtpSession session) {
    if (argument.toUpperCase() == 'F') {
      session.sendResponse('200 Structure set to File');
    } else {
      session.sendResponse('504 Structure not supported');
    }
  }

  void handleMode(String argument, FtpSession session) {
    if (argument.toUpperCase() == 'S') {
      session.sendResponse('200 Mode set to Stream');
    } else {
      session.sendResponse('504 Mode not supported');
    }
  }
}
