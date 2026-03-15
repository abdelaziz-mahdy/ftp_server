import 'platform_output_handler.dart';

class LinuxOutputHandler extends PlatformOutputHandler {
  @override
  String normalizePath(String path) {
    // Linux uses forward slashes
    return path.replaceAll('\\', '/');
  }

  @override
  String getExpectedPwdOutput(String path) => 'Remote directory: $path';

  @override
  String getExpectedSizeOutput(int size) => '\t$size';

  @override
  String getExpectedDirectoryChangeOutput(String path) =>
      '250 Directory changed to $path';

  @override
  String getExpectedDirectoryListingOutput(String listing) =>
      '150 Opening data connection\\r\\n$listing\\r\\n226 Transfer complete\\r\\n';

  @override
  String getExpectedMakeDirectoryOutput(String path) => '257 "$path" created';

  @override
  String getExpectedDeleteDirectoryOutput(String path) =>
      '250 Directory deleted';

  @override
  String getExpectedDeleteFileOutput(String filename) => '250 File deleted';

  @override
  String getExpectedTransferCompleteOutput() => '226 Transfer complete';
}
