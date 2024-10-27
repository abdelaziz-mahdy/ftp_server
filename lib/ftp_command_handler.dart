import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/socket_wrapper/plain_socket_wrapper.dart';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';
import 'logger_handler.dart';

class FTPCommandHandler {
  final SocketWrapper controlSocket;
  final LoggerHandler logger;

  FTPCommandHandler(this.controlSocket, this.logger);

  void handleCommand(String commandLine, FtpSession session) {
    List<String> parts = commandLine.split(' ');
    String command = parts[0].toUpperCase();
    String argument = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';

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
        handleAuth(argument, session);
        break;
      case 'PBSZ':
        handlePbsz(argument, session);
        break;
      case 'PROT':
        handleProt(argument, session);
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

    session.sendResponse(' AUTH TLS');
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
      session.sendResponse('530 Secure connection required.');
    }
  }

  void handleProt(String argument, FtpSession session) {
    if (argument == 'C' || argument == 'P') {
      // Add 'P' for Private (TLS)
      // session.dataChannelProtectionLevel = argument;
      session.sendResponse('200 PROT command successful.');
    } else {
      session.sendResponse('501 Invalid PROT argument.');
    }
  }

  void handleAuth(String argument, FtpSession session) async {
    if (argument.toUpperCase() == 'TLS' &&
        session.secureConnectionAllowed &&
        session.controlSocket is PlainSocketWrapper) {
      session.sendResponse('234 AUTH TLS successful');

      session.controlSocket =
          await (session.controlSocket as PlainSocketWrapper)
              .upgradeToSecure(securityContext: session.securityContext!);

      session.secure = true;
      session.listenToControlMessages();
      session.logger.generalLog('TLS negotiation completed');
    } else {
      session.sendResponse('504 AUTH type not supported');
    }
  }
}
