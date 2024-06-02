import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';

void main() {
  final Directory tempDir = Directory.systemTemp.createTempSync('ftp_test');
  final List<String> allowedDirectories = [tempDir.path];
  late FtpServer server;
  late Process ftpClient;
  const int port = 2126;
  final String logFilePath = '${tempDir.path}/ftpsession.log';

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

  Future<void> connectAndAuthenticate() async {
    ftpClient = await Process.start(
      Platform.isWindows ? 'cmd' : 'bash',
      Platform.isWindows
          ? ['/c', 'ftp', '-n', '-v', '-i', '127.0.0.1', port.toString()]
          : ['-c', 'ftp -n -v -i 127.0.0.1 $port'],
      runInShell: true,
    );
    File(logFilePath).writeAsStringSync(''); // Clear the log file
    ftpClient.stdout.listen((data) {
      File(logFilePath)
          .writeAsStringSync(String.fromCharCodes(data), mode: FileMode.append);
    });
    ftpClient.stderr.listen((data) {
      File(logFilePath)
          .writeAsStringSync(String.fromCharCodes(data), mode: FileMode.append);
    });
    ftpClient.stdin.writeln('open 127.0.0.1 $port');
    await ftpClient.stdin.flush();
    ftpClient.stdin.writeln('user test password');
    await ftpClient.stdin.flush();
  }

  Future<String> readAllOutput() async {
    await Future.delayed(
        const Duration(milliseconds: 500)); // Wait for log to be written
    return File(logFilePath).readAsStringSync();
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
      tempDir.createSync(recursive: true);
      server = FtpServer(
        port,
        username: 'test',
        password: 'password',
        allowedDirectories: allowedDirectories,
        startingDirectory: allowedDirectories.first,
        serverType: ServerType.readAndWrite,
        // ignore: avoid_print
        logFunction: (String message) => print(message),
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      await connectAndAuthenticate();
    });

    tearDown(() async {
      ftpClient.kill();
    });

    test('Authentication Success', () async {
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
      ftpClient.stdin.writeln('cd ${tempDir.path}');
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
      expect(Directory('${tempDir.path}/test_dir').existsSync(), isTrue);
    });

    test('Remove Directory', () async {
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('rmdir test_dir');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();

      expect(output, contains('250 Directory deleted'));
      expect(Directory('${tempDir.path}/test_dir').existsSync(), isFalse);
    });

    test('Store File', () async {
      final testFile = File('${tempDir.path}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('put ${testFile.path}');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();

      expect(output, contains('226 Transfer complete'));
    });

    test('Retrieve File', () async {
      final testFile = File('${tempDir.path}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin
          .writeln('get ${testFile.path} ${tempDir.path}/retrieved_file.txt');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();

      expect(output, contains('226 Transfer complete'));
      expect(File('${tempDir.path}/retrieved_file.txt').existsSync(), isTrue);
    });

    test('File Size', () async {
      final testFile = File('${tempDir.path}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('size ${testFile.path}');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();

      expect(output, contains('213 11')); // File size is 11 bytes
    });

    test('Delete File', () async {
      final testFile = File('${tempDir.path}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('delete ${testFile.path}');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();

      expect(output, contains('250 File deleted'));
      expect(testFile.existsSync(), isFalse);
    });

    test('System Command', () async {
      ftpClient.stdin.writeln('syst');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();

      expect(output, contains('215 UNIX Type: L8'));
    });

    test('Print Working Directory Command', () async {
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      final output = await readAllOutput();

      expect(output, contains('257 "${tempDir.path}" is current directory'));
    });
  });
}
