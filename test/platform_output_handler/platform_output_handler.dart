import 'dart:io';
import 'package:ftp_server/file_operations/file_operations.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

abstract class PlatformOutputHandler {
  String getExpectedPwdOutput(String path);
  String getExpectedSizeOutput(int size);
  String getExpectedDirectoryChangeOutput(String path);
  String getExpectedDirectoryListingOutput(String listing);
  Future<String> generateDirectoryListing(
      String path, FileOperations fileOperations) async {
    StringBuffer listing = StringBuffer();
    var entities = await fileOperations.listDirectory(path);

    for (var entity in entities) {
      var stat = await entity.stat();
      String permissions = _formatPermissions(stat);
      String fileSize = stat.size.toString();
      String modificationTime = _formatModificationTime(stat.modified);
      String fileName = p.basename(entity.path);

      listing.writeln(
          '$permissions 1 ftp ftp $fileSize $modificationTime $fileName');
    }

    return listing.toString().trim();
  }

  String _formatPermissions(FileStat stat) {
    String type = stat.type == FileSystemEntityType.directory ? 'd' : '-';
    String owner = _permissionToString(stat.mode >> 6);
    String group = _permissionToString((stat.mode >> 3) & 7);
    String others = _permissionToString(stat.mode & 7);
    return '$type$owner$group$others';
  }

  String _permissionToString(int permission) {
    String read = (permission & 4) != 0 ? 'r' : '-';
    String write = (permission & 2) != 0 ? 'w' : '-';
    String execute = (permission & 1) != 0 ? 'x' : '-';
    return '$read$write$execute';
  }

  String _formatModificationTime(DateTime dateTime) {
    return DateFormat('MMM dd HH:mm').format(dateTime);
  }
}
