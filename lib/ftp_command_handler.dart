import 'dart:io';
import 'package:ftp_server/ftp_session.dart'; // Ensure this path matches your package structure

class FTPCommandHandler {
  final Socket controlSocket;
 
  FTPCommandHandler(this.controlSocket);

  void handleCommand(String commandLine, FtpSession session) {
    List<String> parts = commandLine.split(' ');
    String command = parts[0].toUpperCase();
    String argument = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    print('Command: $command, Argument: $argument');
    // Using a switch or if-else chain to handle different commands
    switch (command) {
      case 'USER':
        // Process USER command
        session.cachedUsername = argument;
        session.isAuthenticated =
            false; // Reset authentication status pending password check
        session.sendResponse('331 Password required for $argument');
        break;
      case 'PASS':
        // Process PASS command, typically you would check against a stored password
        if ((session.username == null && session.password == null) ||
            (session.cachedUsername == session.username && argument == session.password)) {
          // Replace with your authentication logic
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
        session.storeFile(argument);
        break;
      case 'PWD':
        session.sendResponse(
            '257 "${session.currentDirectory}" is the current directory');
        break;
      case 'CWD':
        session.changeDirectory(argument);
        break;
      case 'MKD':
        session.makeDirectory(argument);
        break;
      case 'RMD':
        session.removeDirectory(argument);
        break;
      case 'DELE':
        session.deleteFile(argument);
        break;
      case 'SYST':
        session.sendResponse(
            '215 UNIX Type: L8'); // Assuming a UNIX-type system for simplicity
        break;
      case 'NOOP':
        session.sendResponse('200 NOOP command successful');
        break;
      case 'TYPE':
        // Typically responds to A (ASCII) or I (binary) types
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
