import 'dart:io';
import 'package:ftp_server/ftp_session.dart';
import 'package:ftp_server/server_type.dart';
// Import the enum

class FTPCommandHandler {
  final Socket controlSocket;

  FTPCommandHandler(this.controlSocket);

  void handleCommand(String commandLine, FtpSession session) {
    List<String> parts = commandLine.split(' ');
    String command = parts[0].toUpperCase();
    String argument = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    print('Command: $command, Argument: $argument');

    switch (command) {
      case 'USER':
        session.cachedUsername = argument;
        session.isAuthenticated =
            false; // Reset authentication status pending password check
        session.sendResponse('331 Password required for $argument');
        break;
      case 'PASS':
        if ((session.username == null && session.password == null) ||
            (session.cachedUsername == session.username &&
                argument == session.password)) {
          session.isAuthenticated = true;
          session.sendResponse('230 User logged in, proceed');
        } else {
          session.sendResponse('530 Not logged in');
        }
        break;
      case 'QUIT':
        session.sendResponse('221 Service closing control connection');
        session.controlSocket.close();
        break;
      case 'PASV':
        session.enterPassiveMode();
        break;
      case 'PORT':
        session.enterActiveMode(argument);
        break;
      case 'LIST':
        session.listDirectory(argument);
        break;
      case 'RETR':
        session.retrieveFile(argument);
        break;
      case 'STOR':
        if (session.serverType == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          session.storeFile(argument);
        }
        break;
      case 'CWD':
        session.changeDirectory(argument);
        break;
      case 'CDUP':
        session.changeToParentDirectory();
        break;
      case 'MKD':
        if (session.serverType == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          session.makeDirectory(argument);
        }
        break;
      case 'RMD':
        if (session.serverType == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          session.removeDirectory(argument);
        }
        break;
      case 'DELE':
        if (session.serverType == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          session.deleteFile(argument);
        }
        break;
      case 'SYST':
        session.sendResponse(
            '215 UNIX Type: L8'); // Assuming a UNIX-type system for simplicity
        break;
      case 'NOOP':
        session.sendResponse('200 NOOP command successful');
        break;
      case 'TYPE':
        if (argument == 'A' || argument == 'I') {
          session.sendResponse('200 Type set to $argument');
        } else {
          session.sendResponse('500 Syntax error, command unrecognized');
        }
        break;
      case 'SIZE':
        session.fileSize(argument);
        break;
      default:
        session.sendResponse('502 Command not implemented');
        break;
    }
  }
}
