import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';

void main() {
  final List<String> allowedDirectories = ["/tmp/ftp_test"];
  late FtpServer server;
  late Process ftpClient;
  final int port = 2126;
  final String logFilePath = 'ftpsession.log';

  Future<bool> isFtpAvailable() async {
    try {
      final result = await Process.run('ftp', ['-v'], runInShell: true);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  Future<void> installFtp() async {
    if (Platform.isLinux) {
      await Process.run('sudo', ['apt-get', 'update'], runInShell: true);
      await Process.run('sudo', ['apt-get', 'install', '-y', 'ftp'],
          runInShell: true);
    } else if (Platform.isMacOS) {
      await Process.run('brew', ['install', 'inetutils'], runInShell: true);
    } else if (Platform.isWindows) {
      // FTP command should be available on Windows by default
    }
  }

  group('FTP Server Tests', () {
    setUpAll(() async {
      // Ensure the ftp command is available
      if (!await isFtpAvailable()) {
        await installFtp();
      }

      if (!await isFtpAvailable()) {
        throw Exception(
            'FTP command is not available and could not be installed.');
      }

      // Create the allowed directory and start the FTP server
      Directory(allowedDirectories.first).createSync(recursive: true);
      server = FtpServer(
        port,
        username: 'test',
        password: 'password',
        allowedDirectories: allowedDirectories,
        startingDirectory: allowedDirectories.first,
        serverType: ServerType.readAndWrite,
        logFunction: (String message) => print(message),
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
      Directory(allowedDirectories.first).deleteSync(recursive: true);
    });

    setUp(() async {
      ftpClient = await Process.start(
        'bash',
        ['-c', 'ftp -n -v -i 127.0.0.1 $port >> $logFilePath'],
        runInShell: true,
      );
      File(logFilePath).writeAsStringSync(''); // Clear the log file
      ftpClient.stdin.writeln('open 127.0.0.1 $port');
      ftpClient.stdin.writeln('user test password');

      await ftpClient.stdin.flush();
    });

    tearDown(() async {
      ftpClient.kill();
    });

    Future<String> readAllOutput() async {
      await Future.delayed(
          Duration(milliseconds: 500)); // Wait for log to be written
      return File(logFilePath).readAsStringSync();
    }

    test('Authentication Success', () async {
      ftpClient.stdin.writeln('user test password');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('230 User logged in, proceed'));
    });

    test('List Directory', () async {
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('226 Transfer complete'));
    });

    test('Change Directory', () async {
      ftpClient.stdin.writeln('cd /tmp/ftp_test');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('250 Directory changed'));
    });

    test('Make Directory', () async {
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('257 "test_dir" created'));
      expect(Directory('/tmp/ftp_test/test_dir').existsSync(), isTrue);
    });

    test('Remove Directory', () async {
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('rmdir test_dir');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('250 Directory deleted'));
      expect(Directory('/tmp/ftp_test/test_dir').existsSync(), isFalse);
    });

    test('Store File', () async {
      final testFile = File('/tmp/ftp_test/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('put /tmp/ftp_test/test_file.txt');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      await Future.delayed(Duration(milliseconds: 500));
      final output = await readAllOutput();

      expect(output, contains('226 Transfer complete'));
    });

    test('Retrieve File', () async {
      final testFile = File('/tmp/ftp_test/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln(
          'get /tmp/ftp_test/test_file.txt /tmp/ftp_test/retrieved_file.txt');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('226 Transfer complete'));
      expect(File('/tmp/ftp_test/retrieved_file.txt').existsSync(), isTrue);
    });

    test('Delete File', () async {
      final testFile = File('/tmp/ftp_test/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('delete /tmp/ftp_test/test_file.txt');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('250 File deleted'));
      expect(testFile.existsSync(), isFalse);
    });

    test('File Size', () async {
      final testFile = File('/tmp/ftp_test/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('size /tmp/ftp_test/test_file.txt');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('213 11')); // File size is 12 bytes
    });

    test('System Command', () async {
      ftpClient.stdin.writeln('syst');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('215 UNIX Type: L8'));
    });

    test('No Operation Command', () async {
      ftpClient.stdin.writeln('noop');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();
      expect(output, contains('200 NOOP command successful'));
    });
  });
}
