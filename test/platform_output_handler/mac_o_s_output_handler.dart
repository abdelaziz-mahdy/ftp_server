import 'platform_output_handler.dart';

class MacOSOutputHandler extends PlatformOutputHandler {
  @override
  String normalizePath(String path) {
    // macOS uses forward slashes
    return path.replaceAll('\\', '/');
  }

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
      '150 Opening data connection\\n$listing\\n226 Transfer complete\\n';

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
