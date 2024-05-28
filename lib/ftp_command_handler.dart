import 'dart:io';
import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
import 'logger_handler.dart';

class FTPCommandHandler {
  final Socket controlSocket;
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
        handleMkd(argument, session);
        break;
      case 'RMD':
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

  void handleQuit(FtpSession session) {
    session.sendResponse('221 Service closing control connection');
    session.controlSocket.close();
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
}
