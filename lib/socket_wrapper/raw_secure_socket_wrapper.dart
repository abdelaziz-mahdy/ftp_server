import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ftp_server/socket_wrapper/socket_wrapper.dart';

/// Wraps a [RawSecureSocket] to implement [SocketWrapper] with proper
/// TLS shutdown using [RawSecureSocket.shutdown].
///
/// Unlike [SecureSocket], [RawSecureSocket] exposes
/// `shutdown(SocketDirection.send)` which sends TLS close_notify
/// without closing the read side. This allows proper two-phase TLS
/// shutdown required by strict clients like FileZilla (GnuTLS).
class RawSecureSocketWrapper implements SocketWrapper {
  final RawSecureSocket _socket;
  final StreamController<List<int>> _dataController =
      StreamController<List<int>>();
  late StreamSubscription<RawSocketEvent> _rawSub;
  Completer<void>? _peerCloseCompleter;
  bool _shutdownSend = false;

  RawSecureSocketWrapper(this._socket) {
    _socket.readEventsEnabled = true;
    _socket.writeEventsEnabled = false;

    _rawSub = _socket.listen((event) {
      switch (event) {
        case RawSocketEvent.read:
          final data = _socket.read();
          if (data != null && !_dataController.isClosed) {
            if (_shutdownSend) {
              // During close: discard peer's data to empty receive buffer
            } else {
              _dataController.add(data);
            }
          }
          break;
        case RawSocketEvent.readClosed:
          if (!_dataController.isClosed) _dataController.close();
          if (_peerCloseCompleter != null && !_peerCloseCompleter!.isCompleted) {
            _peerCloseCompleter!.complete();
          }
          break;
        case RawSocketEvent.closed:
          if (!_dataController.isClosed) _dataController.close();
          if (_peerCloseCompleter != null && !_peerCloseCompleter!.isCompleted) {
            _peerCloseCompleter!.complete();
          }
          break;
        case RawSocketEvent.write:
          break;
      }
    }, onDone: () {
      if (!_dataController.isClosed) _dataController.close();
      if (_peerCloseCompleter != null && !_peerCloseCompleter!.isCompleted) {
        _peerCloseCompleter!.complete();
      }
    }, onError: (e) {
      if (!_dataController.isClosed) {
        _dataController.addError(e);
        _dataController.close();
      }
      if (_peerCloseCompleter != null && !_peerCloseCompleter!.isCompleted) {
        _peerCloseCompleter!.complete();
      }
    });
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
  Future<void> flush() async {
    // RawSecureSocket writes go through the TLS layer to the OS buffer.
    // There's no explicit flush, but the data is written immediately.
  }

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _dataController.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<void> close() async {
    // Proper two-phase TLS shutdown:
    //
    // 1. shutdown(send) → sends TLS close_notify + TCP FIN,
    //    but keeps the read side OPEN so we can drain the peer's response.
    //
    // 2. Wait for the peer's close_notify (readClosed event).
    //    This empties the OS receive buffer, preventing TCP RST.
    //
    // 3. Fully close the socket. Since the receive buffer is empty,
    //    the OS sends a clean TCP FIN instead of RST.
    //
    // Without this, SecureSocket.close() shuts both sides at once,
    // leaving the peer's close_notify unread in the receive buffer,
    // which causes the OS to send RST — discarding our close_notify
    // before it reaches the client (FileZilla GnuTLS error -110).

    _shutdownSend = true;
    _socket.shutdown(SocketDirection.send);

    _peerCloseCompleter ??= Completer<void>();
    try {
      await _peerCloseCompleter!.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Timeout: peer didn't close in time — force close
    }

    _rawSub.cancel();
    if (!_dataController.isClosed) _dataController.close();
    await _socket.close();
  }

  @override
  void destroy() {
    _rawSub.cancel();
    if (!_dataController.isClosed) _dataController.close();
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
