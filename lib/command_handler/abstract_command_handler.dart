import '../session/abstract_session.dart';

abstract class CommandHandler {
  void handleCommand(String commandLine, FtpSession session);
}
