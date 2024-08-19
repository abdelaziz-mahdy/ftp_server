import 'dart:convert';
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
  Future<String> execFTPCmdOnWin(String commands) async {
    // FTP 服务器的地址、用户名和密码
    const String ftpHost = '127.0.0.1 $port';
    const String user = 'test';
    const String password = 'password';
    // Shell 命令连接 FTP 服务器并执行操作
    String command = '''
open $ftpHost
user $user
$password

$commands
quit
''';

    // 创建临时脚本文件
    File scriptFile = File('ftp_win_script.txt');
    await scriptFile.writeAsString(command);

    try {
      // 运行 FTP 命令
      ProcessResult result = await Process.run(
          'ftp', ['-n', '-v', '-s:ftp_win_script.txt'],
          runInShell: true);

      // 输出结果
      return result.stdout + result.stderr;
    } catch (e) {
      // print('Error: $e');
    } finally {
      // 删除临时脚本文件
      await scriptFile.delete();
    }

    return "";
  }

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
      Platform.isWindows ? 'ftp' : 'bash',
      Platform.isWindows ? ['-n', '-v'] : ['-c', 'ftp -n -v'],
      runInShell: true,
    );

    File(logFilePath).writeAsStringSync(''); // Clear the log file
    ftpClient.stdout.transform(utf8.decoder).listen((data) {
      File(logFilePath).writeAsStringSync(data, mode: FileMode.append);
    });
    ftpClient.stderr.transform(utf8.decoder).listen((data) {
      File(logFilePath).writeAsStringSync(data, mode: FileMode.append);
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

      var output = await readAllOutput();

      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("quit");
      }

      expect(output, contains('230 User logged in, proceed'));
    });

    test('List Directory', () async {
      ftpClient.stdin.writeln('ls');
      if (Platform.isLinux) {
        ftpClient.stdin.writeln('passive on');
        ftpClient.stdin.writeln('ls');
        ftpClient.stdin.writeln('passive off');
      }
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput();

      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("ls");
      }

      expect(output, contains('226 Transfer complete'));
    });

    test('Change Directory', () async {
      ftpClient.stdin.writeln('cd ${tempDir.path}');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput();

      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("cd ${tempDir.path}");
      }

      expect(output, contains('250 Directory changed'));
    });

    test('Make Directory', () async {
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput();

      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("mkdir test_dir \nls");
      }

      expect(output, contains('257 "test_dir" created'));
      expect(output, contains('test_dir'));
      expect(Directory('${tempDir.path}/test_dir').existsSync(), isTrue);
    });

    test('Remove Directory', () async {
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('rmdir test_dir');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput();

      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("mkdir test_dir\nrmdir test_dir");
        expect(output, contains('250 Directory deleted'));
        output = await execFTPCmdOnWin("ls");
        expect(output, isNot(contains('test_dir')));
      } else {
        expect(output, contains('250 Directory deleted'));
        expect(output, isNot(contains('test_dir')));
      }

      expect(Directory('${tempDir.path}/test_dir').existsSync(), isFalse);
    });

    test('Store File', () async {
      final testFile = File('${tempDir.path}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('put ${testFile.path}');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput();

      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("put ${testFile.path}");
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output, contains('226 Transfer complete'));
      }

      expect(output, contains('test_file.txt'));
    });

    test('Retrieve File', () async {
      final testPath = '${tempDir.path}/test_file_ret.txt';
      final testFile = File(testPath)..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('get ${testFile.path} $testPath');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput();

      if (Platform.isWindows) {
        output = await execFTPCmdOnWin('get ${testFile.path} $testPath');
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin('dir');
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(File(testPath).existsSync(), isTrue);
    });

    test('Delete File', () async {
      final testFile = File('${tempDir.path}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('delete ${testFile.path}');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput();
      if (Platform.isWindows) {
        output = (await execFTPCmdOnWin('delete ${testFile.path}'));
        expect(output, contains('250 File deleted'));
        output = (await execFTPCmdOnWin('dir'));
      } else {
        expect(output, contains('250 File deleted'));
      }
      expect(output, isNot(contains('test_file.txt')));
      expect(testFile.existsSync(), isFalse);
    });

    if (!Platform.isWindows) {
      test('File Size', () async {
        final testFile = File('${tempDir.path}/test_file.txt')
          ..writeAsStringSync('Hello, FTP!');

        ftpClient.stdin.writeln('size ${testFile.path}');
        ftpClient.stdin.writeln('ls');
        ftpClient.stdin.writeln('quit');
        await ftpClient.stdin.flush();

        var output = await readAllOutput();

        var expectText = '213 11';
        if (Platform.isLinux) {
          expectText = '\t11';
        }

        expect(output, contains(expectText)); // File size is 11 bytes
        expect(output, contains('test_file.txt'));
      });

      test('System Command', () async {
        ftpClient.stdin.writeln('syst');
        ftpClient.stdin.writeln('quit');
        await ftpClient.stdin.flush();

        var output = await readAllOutput();

        expect(output, contains('215 UNIX Type: L8'));
      });
    }

    test('Print Working Directory Command', () async {
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput();

      if (Platform.isWindows) {
        output = await execFTPCmdOnWin('pwd');
      }

      var expectText =
          '257 "${tempDir.path.replaceAll("\\\\", "/")}" is current directory';
      if (Platform.isLinux) {
        expectText = 'Remote directory: ${tempDir.path}';
      }

      expect(output, contains(expectText));
    });
    test('List Nested Directories', () async {
      // Step 1: Create nested directories
      final nestedDirPath = '${tempDir.path}/outer_dir/inner_dir';
      Directory(nestedDirPath).createSync(recursive: true);

      // Step 2: Change directory to the outer directory
      ftpClient.stdin.writeln('cd ${tempDir.path}/outer_dir');
      ftpClient.stdin.writeln('pwd'); // To check we're in the right directory

      // Step 3: List directories inside the outer directory
      ftpClient.stdin.writeln('ls');

      // Step 4: Change directory to the inner directory
      ftpClient.stdin.writeln('cd inner_dir');
      ftpClient.stdin.writeln('pwd'); // To check we're in the right directory

      // Step 5: List directories inside the inner directory
      ftpClient.stdin.writeln('ls');

      // Step 6: Quit FTP session
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      // Step 7: Read the output log
      var output = await readAllOutput();

      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            'cd ${tempDir.path}/outer_dir\npwd\nls\ncd inner_dir\npwd\nls');
      }

      // Expected directory paths
      final expectedOuterDir =
          '${tempDir.path.replaceAll("\\", "/")}/outer_dir';
      final expectedInnerDir =
          '${tempDir.path.replaceAll("\\", "/")}/outer_dir/inner_dir';

      // Step 8: Check that the output contains the expected directories
      expect(output, contains('250 Directory changed'));
      expect(output, contains('257 "$expectedOuterDir" is current directory'));
      expect(output, contains('inner_dir'));

      expect(output, contains('250 Directory changed'));
      expect(output, contains('257 "$expectedInnerDir" is current directory'));
    });
  });
}
