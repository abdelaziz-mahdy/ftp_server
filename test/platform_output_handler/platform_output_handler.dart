abstract class PlatformOutputHandler {
  String getExpectedPwdOutput(String path);
  String getExpectedSizeOutput(int size);
  String getExpectedDirectoryChangeOutput(String path);
  String getExpectedDirectoryListingOutput(String listing);
}
