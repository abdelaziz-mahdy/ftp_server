import 'platform_output_handler.dart';

class WindowsOutputHandler extends PlatformOutputHandler {
  @override
  String normalizePath(String path) {
    // Windows uses backslashes
    return path.replaceAll('/', '\\');
  }

  @override
  String getExpectedPwdOutput(String path) =>
      '257 "${path.replaceAll("/", "\\")}" is current directory';

  @override
  String getExpectedSizeOutput(int size) => '213 $size';

  @override
  String getExpectedDirectoryChangeOutput(String path) =>
      '250 Directory changed to ${path.replaceAll("/", "\\")}';

  @override
  String getExpectedDirectoryListingOutput(String listing) =>
      '125 Data connection already open; Transfer starting\r\n$listing\r\n226 Transfer complete\r\n';
  @override
  String getExpectedMakeDirectoryOutput(String path) =>
      '257 "${path.replaceAll("/", "\\")}" created';

  @override
  String getExpectedDeleteDirectoryOutput(String path) =>
      '250 Directory deleted';

  @override
  String getExpectedDeleteFileOutput(String filename) => '250 File deleted';

  @override
  String getExpectedTransferCompleteOutput() => '226 Transfer complete';
}
