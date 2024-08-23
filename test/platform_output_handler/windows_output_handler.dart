import 'platform_output_handler.dart';

class WindowsOutputHandler extends PlatformOutputHandler {
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
}
