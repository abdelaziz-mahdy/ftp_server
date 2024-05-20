// lib/file_system/in_memory_file_system.dart
import 'abstract_file_system.dart';

class InMemoryFileEntry implements FileEntry {
  @override
  final String name;
  @override
  DateTime lastModified;
  @override
  int size;

  InMemoryFileEntry(this.name, this.lastModified, this.size);
}

class InMemoryFtpFile extends InMemoryFileEntry implements FtpFile {
  List<int> _data;

  InMemoryFtpFile(String name, DateTime lastModified, this._data)
      : super(name, lastModified, _data.length);

  @override
  List<int> read() {
    return _data;
  }

  @override
  void write(List<int> data) {
    _data = data;
    // Update size and last modified time
    lastModified = DateTime.now();
    size = _data.length;
  }
}

class InMemoryFtpDirectory extends InMemoryFileEntry implements FtpDirectory {
  final List<FileEntry> _entries = [];

  InMemoryFtpDirectory(String name)
      : super(name, DateTime.now(), 0); // Size is 0 for directories

  @override
  List<FileEntry> listEntries() {
    return _entries;
  }

  @override
  void addEntry(FileEntry entry) {
    _entries.add(entry);
  }

  @override
  void removeEntry(String name) {
    _entries.removeWhere((entry) => entry.name == name);
  }
}
