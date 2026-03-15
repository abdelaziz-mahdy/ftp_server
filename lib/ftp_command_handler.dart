import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'logger_handler.dart';

class FTPCommandHandler {
  final LoggerHandler logger;

  FTPCommandHandler(this.logger);

  /// Commands that are allowed before authentication
  static const _preAuthCommands = {
    'USER', 'PASS', 'QUIT', 'FEAT', 'SYST', 'NOOP', 'OPTS',
  };

  Future<void> handleCommand(String commandLine, FtpSession session) async {
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
        await handleQuit(session);
        break;
      case 'PASV':
        await session.enterPassiveMode();
        break;
      case 'PORT':
        await session.enterActiveMode(argument);
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
        session.sendResponse('202 ALLO command not needed');
        break;
      case 'STAT':
        session.sendResponse('211 Server is running');
        break;
      case 'HELP':
        handleHelp(session);
        break;
      case 'SITE':
        session.sendResponse('502 SITE command not implemented');
        break;
      case 'ACCT':
        session.sendResponse('202 ACCT command not needed');
        break;
      case 'REIN':
        session.isAuthenticated = false;
        session.cachedUsername = null;
        session.sendResponse('220 Service ready for new user');
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
    session.sendResponse('331 Password required for $argument');
  }

  void handlePass(String argument, FtpSession session) {
    if (session.cachedUsername == null) {
      session.sendResponse('503 Bad sequence of commands');
      return;
    }
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
    session.closeConnection();
  }

  /// Strips LIST flags (e.g., -la, -a) that clients like FileZilla send.
  /// Only strips tokens that look like flags (start with '-' and contain
  /// no path separators), preserving valid paths like "-backups".
  String _stripListFlags(String argument) {
    if (argument.isEmpty) return argument;
    final parts = argument.split(' ');
    final filtered = parts.where((p) {
      return !(p.startsWith('-') && !p.contains('/') && !p.contains('\\'));
    }).join(' ').trim();
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
    session.sendResponse('211-Features:');
    session.sendResponse(' SIZE');
    session.sendResponse(' MDTM');
    session.sendResponse(' MLSD');
    session.sendResponse(' EPSV');
    session.sendResponse(' PASV');
    session.sendResponse(' UTF8');
    session.sendResponse('211 End');
  }

  Future<void> handleEpsv(String argument, FtpSession session) async {
    if (argument.toUpperCase() == 'ALL') {
      session.sendResponse('200 EPSV ALL command successful');
    } else {
      await session.enterExtendedPassiveMode();
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

  void handleHelp(FtpSession session) {
    session.sendResponse('214-The following commands are supported:');
    session.sendResponse(
        ' USER PASS QUIT PASV PORT EPSV LIST NLST RETR STOR');
    session.sendResponse(
        ' CWD CDUP MKD RMD DELE PWD TYPE SIZE FEAT OPTS SYST');
    session.sendResponse(
        ' NOOP ABOR MLSD MDTM RNFR RNTO STRU MODE ALLO HELP');
    session.sendResponse('214 End');
  }
}
