import 'dart:io';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:path/path.dart' as p;
import 'package:pure_ftp/pure_ftp.dart';
import 'package:test/test.dart';

void main() {
  group('FTPS tests using pure_ftp', () {
    late FtpClient ftpClient;
    const int port = 2127; // Or your FTPS port
    final Directory tempDir = Directory.systemTemp.createTempSync('ftps_test');
    final String uploadFilePath = '${tempDir.path}/upload.txt';
    final String downloadFilePath = '${tempDir.path}/download.txt';
    final String testFileName = 'testfile.txt';
    final String testDirName = 'test_dir';
    late FtpServer server;

    setUpAll(() async {
      File(uploadFilePath)
          .writeAsStringSync('This is the upload file content.');
      ftpClient = FtpClient(
        socketInitOptions: FtpSocketInitOptions(
          host: '127.0.0.1',
          port: port,
          securityType: SecurityType.FTPES, // Explicit FTPS
          transferType: FtpTransferType.binary,
        ),
        authOptions: const FtpAuthOptions(
          username: 'test', // Replace with your FTP username
          password: 'password', // Replace with your FTP password
        ),
      );
      server = FtpServer(
        port,
        username: 'test',
        password: 'password',
        sharedDirectories: [tempDir.path],
        startingDirectory: p.basename(tempDir.path),
        serverType: ServerType.readAndWrite,
        logFunction: (String message) => print(message),
      );
      await server.startInBackground();
      await ftpClient.connect();
    });

    tearDownAll(() async {
      await ftpClient.disconnect();
      tempDir.deleteSync(recursive: true);
    });

    test('Upload file', () async {
      final file = ftpClient.getFile(testFileName);
      final result = await ftpClient.fs.uploadFile(
        file,
        File(uploadFilePath).readAsBytesSync(),
      );
      expect(result, isTrue);
    });

    test('Download file', () async {
      final file = ftpClient.getFile(testFileName);
      final downloadedData = await ftpClient.fs.downloadFile(file);
      File(downloadFilePath).writeAsBytesSync(downloadedData);
      expect(
        File(downloadFilePath).readAsStringSync(),
        equals('This is the upload file content.'),
      );
    });

    test('List directory', () async {
      final entries = await ftpClient.fs.listDirectory(listType: ListType.MLSD);
      expect(entries.map((e) => e.name).toList(), contains(testFileName));
    });

    test('Make directory', () async {
      final dir = ftpClient.getDirectory(testDirName);
      final result = await dir.create();
      expect(result, isTrue);
      final entries = await ftpClient.fs.listDirectory(listType: ListType.MLSD);

      expect(entries.map((e) => e.name).toList(), contains(testDirName));
    });

    test('Change directory', () async {
      final success = await ftpClient.changeDirectory(testDirName);
      expect(success, true);
      expect(ftpClient.fs.currentDirectory.name, equals(testDirName));
    });

    test('Change to parent directory', () async {
      final success = await ftpClient.changeDirectoryUp();
      expect(success, true);
      expect(ftpClient.fs.currentDirectory.name, isNot(equals(testDirName)));
    });

    test('Rename file', () async {
      final file = ftpClient.getFile(testFileName);
      final renamedFile = await file.rename('renamed_$testFileName');
      expect(renamedFile.name, equals('renamed_$testFileName'));

      final entries = await ftpClient.fs.listDirectory(listType: ListType.MLSD);

      expect(entries.map((e) => e.name).toList(),
          contains('renamed_$testFileName'));
    });

    test('Delete file', () async {
      final file = ftpClient.getFile('renamed_$testFileName');
      final result = await file.delete();
      expect(result, isTrue);
    });

    test('Remove directory', () async {
      final dir = ftpClient.getDirectory(testDirName);
      final result = await dir.delete();

      expect(result, isTrue);

      final entries = await ftpClient.fs.listDirectory(listType: ListType.MLSD);

      expect(entries.map((e) => e.name).toList(), isNot(contains(testDirName)));
    });
  });
}
