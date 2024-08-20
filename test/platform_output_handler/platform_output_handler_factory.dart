import 'dart:io';
import 'linux_output_handler.dart';
import 'mac_o_s_output_handler.dart';
import 'platform_output_handler.dart';
import 'windows_output_handler.dart';

class PlatformOutputHandlerFactory {
  static PlatformOutputHandler create() {
    if (Platform.isLinux) {
      return LinuxOutputHandler();
    } else if (Platform.isMacOS) {
      return MacOSOutputHandler();
    } else if (Platform.isWindows) {
      return WindowsOutputHandler();
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}
