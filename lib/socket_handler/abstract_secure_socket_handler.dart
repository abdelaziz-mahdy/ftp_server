// lib/socket_handler.dart

import 'dart:io';
import 'package:ftp_server/socket_handler/abstract_socket_handler.dart';

abstract class AbstractSecureSocketHandler extends AbstractSocketHandler {
  SecurityContext securityContext;
  AbstractSecureSocketHandler(this.securityContext);
}
