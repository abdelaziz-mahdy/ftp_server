
abstract class FileEntry {
  String get name;
  DateTime get lastModified;
  int get size;
}

abstract class FtpFile extends FileEntry {
  List<int> read();
  void write(List<int> data);
}

abstract class FtpDirectory extends FileEntry {
  List<FileEntry> listEntries();
  void addEntry(FileEntry entry);
  void removeEntry(String name);
}
