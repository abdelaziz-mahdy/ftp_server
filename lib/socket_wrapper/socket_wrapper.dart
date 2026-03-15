// lib/services/certificate_service.dart

import 'dart:async';
import 'dart:io';

abstract class SocketWrapper {
  Future<void> close();
  void add(List<int> data);
  Future<void> flush();
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError});
  void destroy(); // For abrupt closures if needed
  void write(Object obj);

  /// The port used by this socket.
  ///
  /// Throws a [SocketException] if the socket is closed.
  /// The port is 0 if the socket is a Unix domain socket.
  int get port;

  /// The remote port connected to by this socket.
  ///
  /// Throws a [SocketException] if the socket is closed.
  /// The port is 0 if the socket is a Unix domain socket.
  int get remotePort;

  /// The [InternetAddress] used to connect this socket.
  ///
  /// Throws a [SocketException] if the socket is closed.
  InternetAddress get address;

  /// The remote [InternetAddress] connected to by this socket.
  ///
  /// Throws a [SocketException] if the socket is closed.
  InternetAddress get remoteAddress;
}
