import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ftp_server/socket_wrapper/raw_secure_socket_wrapper.dart';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';

/// Wraps a [RawSocket] to implement [SocketWrapper].
///
/// Used for data channel connections that will be upgraded to TLS.
/// Unlike [PlainSocketWrapper] (which wraps [Socket]), this wraps
/// the lower-level [RawSocket], enabling upgrade to [RawSecureSocket]
/// which provides proper TLS shutdown via `shutdown(SocketDirection.send)`.
///
/// Does NOT subscribe to the raw socket on construction — the subscription
/// is deferred until [listen] is called or until [upgradeToSecure] takes
/// ownership. This avoids the single-subscription stream issue where
/// cancelling a subscription prevents [RawSecureSocket.secureServer] from
/// creating a new one.
class RawSocketWrapper implements SocketWrapper {
  final RawSocket _socket;

  RawSocketWrapper(this._socket);

  /// Upgrades this plain socket to a TLS-secured socket.
  ///
  /// Returns a [RawSecureSocketWrapper] that provides proper TLS shutdown.
  /// The raw socket is handed to [RawSecureSocket.secureServer] which
  /// creates its own subscription internally.
  Future<RawSecureSocketWrapper> upgradeToSecure({
    required SecurityContext securityContext,
  }) async {
    final secureRaw = await RawSecureSocket.secureServer(
      _socket,
      securityContext,
    );
    return RawSecureSocketWrapper(secureRaw);
  }

  @override
  void write(Object obj) {
    add(utf8.encode(obj.toString()));
  }

  @override
  void add(List<int> data) {
    int offset = 0;
    while (offset < data.length) {
      final written = _socket.write(data, offset, data.length - offset);
      if (written <= 0) break;
      offset += written;
    }
  }

  @override
  Future<void> flush() async {}

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final controller = StreamController<List<int>>();
    _socket.readEventsEnabled = true;
    _socket.listen((event) {
      switch (event) {
        case RawSocketEvent.read:
          final data = _socket.read();
          if (data != null && !controller.isClosed) controller.add(data);
          break;
        case RawSocketEvent.readClosed:
        case RawSocketEvent.closed:
          if (!controller.isClosed) controller.close();
          break;
        case RawSocketEvent.write:
          break;
      }
    }, onDone: () {
      if (!controller.isClosed) controller.close();
    }, onError: (e) {
      if (!controller.isClosed) {
        controller.addError(e);
        controller.close();
      }
    });

    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<void> close() async {
    await _socket.close();
  }

  @override
  void destroy() {
    _socket.close();
  }

  @override
  int get port => _socket.port;

  @override
  int get remotePort => _socket.remotePort;

  @override
  InternetAddress get address => _socket.address;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
}
