import 'platform_output_handler.dart';

class MacOSOutputHandler extends PlatformOutputHandler {
  @override
  String getExpectedPwdOutput(String path) =>
      '257 "$path" is current directory';

  @override
  String getExpectedSizeOutput(int size) => '213 $size';

  @override
  String getExpectedDirectoryChangeOutput(String path) =>
      '250 Directory changed to $path';

  @override
  String getExpectedDirectoryListingOutput(String listing) =>
      '150 Opening data connection\n$listing\n226 Transfer complete\n';
}
