import 'dart:io';
import 'package:ftp_server/session/abstract_session.dart';
import 'package:ftp_server/server_type.dart';
import '../ftp_commands.dart';
import 'abstract_command_handler.dart';

class ConcreteFTPCommandHandler implements CommandHandler {
  final Socket controlSocket;

  ConcreteFTPCommandHandler(this.controlSocket);

  @override
  void handleCommand(String commandLine, FtpSession session) {
    List<String> parts = commandLine.split(' ');
    String command = parts[0].toUpperCase();
    String argument = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';

    print('Command: $command, Argument: $argument');

    FtpCommands? ftpCommand = FtpCommands.values.firstWhere(
      (e) => e.toString() == command,
      orElse: () => FtpCommands.UNKNOWN,
    );

    switch (ftpCommand) {
      case FtpCommands.USER:
        session.setCachedUsername(argument);
        session.setAuthenticated(false);
        session.sendResponse('331 Password required for $argument');
        break;
      case FtpCommands.PASS:
        if ((session.getUsername() == null && session.getPassword() == null) ||
            (session.getCachedUsername() == session.getUsername() &&
                argument == session.getPassword())) {
          session.setAuthenticated(true);
          session.sendResponse('230 User logged in, proceed');
        } else {
          session.sendResponse('530 Not logged in');
        }
        break;
      case FtpCommands.QUIT:
        session.sendResponse('221 Service closing control connection');
        session.closeControlSocket();
        break;
      case FtpCommands.PASV:
        session.enterPassiveMode();
        break;
      case FtpCommands.PORT:
        session.enterActiveMode(argument);
        break;
      case FtpCommands.LIST:
        session.listDirectory(argument);
        break;
      case FtpCommands.RETR:
        session.retrieveFile(argument);
        break;
      case FtpCommands.STOR:
        if (session.getServerType() == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          session.storeFile(argument);
        }
        break;
      case FtpCommands.CWD:
        session.changeDirectory(argument);
        break;
      case FtpCommands.CDUP:
        session.changeToParentDirectory();
        break;
      case FtpCommands.MKD:
        if (session.getServerType() == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          session.makeDirectory(argument);
        }
        break;
      case FtpCommands.RMD:
        if (session.getServerType() == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          session.removeDirectory(argument);
        }
        break;
      case FtpCommands.DELE:
        if (session.getServerType() == ServerType.readOnly) {
          session.sendResponse('550 Command not allowed in read-only mode');
        } else {
          session.deleteFile(argument);
        }
        break;
      case FtpCommands.SYST:
        session.sendResponse('215 UNIX Type: L8');
        break;
      case FtpCommands.NOOP:
        session.sendResponse('200 NOOP command successful');
        break;
      case FtpCommands.TYPE:
        if (argument == 'A' || argument == 'I') {
          session.sendResponse('200 Type set to $argument');
        } else {
          session.sendResponse('500 Syntax error, command unrecognized');
        }
        break;
      case FtpCommands.SIZE:
        session.fileSize(argument);
        break;
      case FtpCommands.REIN:
        session.reinitialize();
        break;
      case FtpCommands.ABOR:
        session.abort();
        break;
      case FtpCommands.RNFR:
        session.renameFrom(argument);
        break;
      case FtpCommands.RNTO:
        session.renameTo(argument);
        break;
      case FtpCommands.REST:
        session.restart(argument);
        break;
      case FtpCommands.STOU:
        session.storeUnique(argument);
        break;
      case FtpCommands.MLSD:
        session.listDirectory(argument, isMachineReadable: true);
        break;
      case FtpCommands.MLST:
        session.listSingle(argument);
        break;
      case FtpCommands.PWD:
        session.printWorkingDirectory();
        break;
      case FtpCommands.OPTS:
        session.setOptions(argument);
        break;
      case FtpCommands.HOST:
        session.setHost(argument);
        break;
      case FtpCommands.MDTM:
        session.modifyTime(argument);
        break;
      case FtpCommands.FEAT:
        session.featureList();
        break;
      case FtpCommands.STAT:
        session.systemStatus();
        break;
      case FtpCommands.AUTH:
        session.authenticate(argument);
        break;
      default:
        session.sendResponse('502 Command not implemented');
        break;
    }
  }
}
