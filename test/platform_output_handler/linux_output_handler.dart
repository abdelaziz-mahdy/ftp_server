import 'platform_output_handler.dart';

class LinuxOutputHandler extends PlatformOutputHandler {
  @override
  String getExpectedPwdOutput(String path) => 'Remote directory: $path';

  @override
  String getExpectedSizeOutput(int size) => '\t$size';

  @override
  String getExpectedDirectoryChangeOutput(String path) =>
      '250 Directory changed to $path';

  @override
  String getExpectedDirectoryListingOutput(String listing) =>
      '150 Opening data connection\r\n$listing\r\n226 Transfer complete\r\n';
}
