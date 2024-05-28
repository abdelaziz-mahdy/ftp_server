class LoggerHandler {
  final Function(String)? logFunction;

  LoggerHandler(this.logFunction);

  void logCommand(String command, String argument) {
    if (logFunction != null) {
      logFunction!('Command: $command, Argument: $argument');
    }
  }

  void logResponse(String response) {
    if (logFunction != null) {
      logFunction!('Response: $response');
    }
  }
}
