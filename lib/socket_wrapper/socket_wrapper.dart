// lib/services/certificate_service.dart

import 'dart:async';

abstract class SocketWrapper {
  Future<void> close();
  void add(List<int> data);
  Future<void> flush();
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError});
  void destroy(); // For abrupt closures if needed
  void write(Object obj);
}
