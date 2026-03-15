// ignore_for_file: avoid_print

import 'dart:io';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:test/test.dart';

/// Check if curl is available and supports FTPS.
Future<bool> isCurlFtpsAvailable() async {
  try {
    final result = await Process.run('curl', ['--version']);
    if (result.exitCode != 0) return false;
    final output = result.stdout.toString();
    return output.contains('ftps');
  } catch (e) {
    return false;
  }
}

void main() {
  late bool curlAvailable;

  setUpAll(() async {
    curlAvailable = await isCurlFtpsAvailable();
    if (!curlAvailable) {
      print('curl with FTPS support not found, skipping curl FTPS tests');
    }
  });

  group('FTPS with curl (explicit FTPS)', () {
    late FtpServer server;
    late Directory tempDir;
    const int port = 2215;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('ftps_curl_test_');
      File('${tempDir.path}/hello.txt').writeAsStringSync('Hello from FTPS!');
      File('${tempDir.path}/data.bin')
          .writeAsBytesSync(List.generate(1024, (i) => i % 256));

      final dirName = tempDir.path.split(Platform.pathSeparator).last;
      server = FtpServer(
        port,
        username: 'testuser',
        password: 'testpass',
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: dirName),
        serverType: ServerType.readAndWrite,
        logFunction: (msg) => print('[FTPS curl] $msg'),
        secureConnectionAllowed: true,
        secureDataConnection: true,
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    test('Directory listing works over FTPS', () async {
      if (!curlAvailable) {
        markTestSkipped('curl with FTPS not available');
        return;
      }

      final result = await Process.run('curl', [
        '--ssl-reqd',
        '--insecure',
        '-u', 'testuser:testpass',
        'ftp://127.0.0.1:$port/',
        '--list-only',
      ]);

      expect(result.exitCode, equals(0),
          reason: 'curl failed: ${result.stderr}');
      expect(result.stdout.toString(), contains('hello.txt'));
      expect(result.stdout.toString(), contains('data.bin'));
    });

    test('File download works over FTPS', () async {
      if (!curlAvailable) {
        markTestSkipped('curl with FTPS not available');
        return;
      }

      final outputFile =
          File('${tempDir.path}/downloaded.txt');

      final result = await Process.run('curl', [
        '--ssl-reqd',
        '--insecure',
        '-u', 'testuser:testpass',
        'ftp://127.0.0.1:$port/hello.txt',
        '-o', outputFile.path,
      ]);

      expect(result.exitCode, equals(0),
          reason: 'curl failed: ${result.stderr}');
      expect(outputFile.existsSync(), isTrue);
      expect(outputFile.readAsStringSync(), equals('Hello from FTPS!'));
    });

    test('Binary file download works over FTPS', () async {
      if (!curlAvailable) {
        markTestSkipped('curl with FTPS not available');
        return;
      }

      final outputFile =
          File('${tempDir.path}/downloaded.bin');

      final result = await Process.run('curl', [
        '--ssl-reqd',
        '--insecure',
        '-u', 'testuser:testpass',
        'ftp://127.0.0.1:$port/data.bin',
        '-o', outputFile.path,
      ]);

      expect(result.exitCode, equals(0),
          reason: 'curl failed: ${result.stderr}');
      expect(outputFile.existsSync(), isTrue);
      expect(outputFile.lengthSync(), equals(1024));
    });

    test('File upload works over FTPS', () async {
      if (!curlAvailable) {
        markTestSkipped('curl with FTPS not available');
        return;
      }

      final uploadFile = File('${tempDir.path}/to_upload.txt');
      uploadFile.writeAsStringSync('Uploaded via FTPS!');

      final result = await Process.run('curl', [
        '--ssl-reqd',
        '--insecure',
        '-u', 'testuser:testpass',
        '-T', uploadFile.path,
        'ftp://127.0.0.1:$port/uploaded.txt',
      ]);

      expect(result.exitCode, equals(0),
          reason: 'curl failed: ${result.stderr}');

      // Verify the file was uploaded
      final uploadedFile = File(
          '${tempDir.path}/uploaded.txt');
      expect(uploadedFile.existsSync(), isTrue);
      expect(uploadedFile.readAsStringSync(), equals('Uploaded via FTPS!'));
    });

    test('Multiple sequential operations work over FTPS', () async {
      if (!curlAvailable) {
        markTestSkipped('curl with FTPS not available');
        return;
      }

      // Operation 1: List
      var result = await Process.run('curl', [
        '--ssl-reqd',
        '--insecure',
        '-u', 'testuser:testpass',
        'ftp://127.0.0.1:$port/',
        '--list-only',
      ]);
      expect(result.exitCode, equals(0),
          reason: 'LIST failed: ${result.stderr}');

      // Operation 2: Download
      result = await Process.run('curl', [
        '--ssl-reqd',
        '--insecure',
        '-u', 'testuser:testpass',
        'ftp://127.0.0.1:$port/hello.txt',
        '-o', '/dev/null',
      ]);
      expect(result.exitCode, equals(0),
          reason: 'RETR failed: ${result.stderr}');

      // Operation 3: List again
      result = await Process.run('curl', [
        '--ssl-reqd',
        '--insecure',
        '-u', 'testuser:testpass',
        'ftp://127.0.0.1:$port/',
        '--list-only',
      ]);
      expect(result.exitCode, equals(0),
          reason: 'Second LIST failed: ${result.stderr}');
    });
  });

  group('Implicit FTPS with curl', () {
    late FtpServer server;
    late Directory tempDir;
    const int port = 2216;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('ftps_implicit_curl_');
      File('${tempDir.path}/secure.txt').writeAsStringSync('Secure content');

      final dirName = tempDir.path.split(Platform.pathSeparator).last;
      server = FtpServer(
        port,
        username: 'testuser',
        password: 'testpass',
        fileOperations: VirtualFileOperations([tempDir.path],
            startingDirectory: dirName),
        serverType: ServerType.readAndWrite,
        logFunction: (msg) => print('[Implicit FTPS curl] $msg'),
        enforceSecureConnections: true,
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    test('Directory listing works over implicit FTPS', () async {
      if (!curlAvailable) {
        markTestSkipped('curl with FTPS not available');
        return;
      }

      final result = await Process.run('curl', [
        '--insecure',
        '-u', 'testuser:testpass',
        'ftps://127.0.0.1:$port/',
        '--list-only',
      ]);

      expect(result.exitCode, equals(0),
          reason: 'curl failed: ${result.stderr}');
      expect(result.stdout.toString(), contains('secure.txt'));
    });

    test('File download works over implicit FTPS', () async {
      if (!curlAvailable) {
        markTestSkipped('curl with FTPS not available');
        return;
      }

      final outputFile =
          File('${tempDir.path}/downloaded_secure.txt');

      final result = await Process.run('curl', [
        '--insecure',
        '-u', 'testuser:testpass',
        'ftps://127.0.0.1:$port/secure.txt',
        '-o', outputFile.path,
      ]);

      expect(result.exitCode, equals(0),
          reason: 'curl failed: ${result.stderr}');
      expect(outputFile.existsSync(), isTrue);
      expect(outputFile.readAsStringSync(), equals('Secure content'));
    });
  });
}
