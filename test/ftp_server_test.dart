import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftp_server/file_operations/file_operations.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'platform_output_handler/platform_output_handler.dart';
import 'platform_output_handler/platform_output_handler_factory.dart';

void main() {
  final PlatformOutputHandler outputHandler =
      PlatformOutputHandlerFactory.create();
  const int port = 2126;

  Future<String> execFTPCmdOnWin(String commands) async {
    const String ftpHost = '127.0.0.1 $port';
    const String user = 'test';
    const String password = 'password';
    String command = '''
    open $ftpHost
    user $user $password
    $commands
    quit
    ''';

    File scriptFile = File('ftp_win_script.txt');
    await scriptFile.writeAsString(command);

    try {
      ProcessResult result = await Process.run(
        'ftp',
        ['-n', '-v', '-s:ftp_win_script.txt'],
        runInShell: true,
      );
      return result.stdout + result.stderr;
    } catch (e) {
      // Handle error
    } finally {
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
    }
  }

  Future<void> connectAndAuthenticate(
      Process ftpClient, String logFilePath) async {
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

  Future<String> readAllOutput(String logFilePath) async {
    await Future.delayed(
        const Duration(milliseconds: 200)); // Wait for log to be written
    return File(logFilePath).readAsStringSync();
  }

  void runTestsForFileOperations(
    String testDescription,
    FileOperations fileOperations,
    List<String> allowedDirectories,
  ) {
    late FtpServer server;
    late Process ftpClient;
    final String logFilePath = '${allowedDirectories.first}/ftpsession.log';

    setUpAll(() async {
      if (!await isFtpAvailable()) {
        await installFtp();
      }
      if (!await isFtpAvailable()) {
        throw Exception(
            'FTP command is not available and could not be installed.');
      }

      server = FtpServer(
        port,
        username: 'test',
        password: 'password',
        fileOperations: fileOperations,
        serverType: ServerType.readAndWrite,
        // ignore: avoid_print
        logFunction: (String message) => print(message),
      );
      await server.startInBackground();

      ftpClient = await Process.start(
        Platform.isWindows ? 'ftp' : 'bash',
        Platform.isWindows ? ['-n', '-v'] : ['-c', 'ftp -n -v'],
        runInShell: true,
      );

      await connectAndAuthenticate(ftpClient, logFilePath);
    });

    tearDownAll(() async {
      await server.stop();
      ftpClient.kill();
    });

    setUp(() async {
      ftpClient = await Process.start(
        Platform.isWindows ? 'ftp' : 'bash',
        Platform.isWindows ? ['-n', '-v'] : ['-c', 'ftp -n -v'],
        runInShell: true,
      );

      await connectAndAuthenticate(ftpClient, logFilePath);
    });

    tearDown(() async {
      ftpClient.kill();
    });

    test('$testDescription: Authentication Success', () async {
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("quit");
      }

      expect(output, contains('230 User logged in, proceed'));
    });

    test('$testDescription: List Directory', () async {
      ftpClient.stdin.writeln('ls');
      if (Platform.isLinux) {
        ftpClient.stdin.writeln('passive on');
        ftpClient.stdin.writeln('ls');
        ftpClient.stdin.writeln('passive off');
      }
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("ls");
      }

      String listing = await outputHandler.generateDirectoryListing(
          fileOperations.getCurrentDirectory(), fileOperations);
      // Normalize both expected and actual output using the replacement function
      String normalizedOutput = outputHandler.normalizeDirectoryListing(output);
      String normalizedExpected =
          outputHandler.normalizeDirectoryListing(listing);
      // Use normalized strings for comparison
      expect(normalizedOutput, contains(normalizedExpected));
    });

    test('$testDescription: Change Directory', () async {
      ftpClient.stdin.writeln('cd /'); // Changed to root directory
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("cd /");
      }

      String expectedOutput =
          outputHandler.getExpectedDirectoryChangeOutput('/');

      expect(output, contains(expectedOutput));
    });

    test('$testDescription: Make Directory', () async {
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("mkdir test_dir\nls");
      }

      expect(output, contains('257 "test_dir" created'));
      expect(output, contains('test_dir'));
      expect(Directory('${allowedDirectories.first}/test_dir').existsSync(),
          isTrue);
    });

    test('$testDescription: Remove Directory', () async {
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('rmdir test_dir');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("mkdir test_dir\nrmdir test_dir");
        expect(output, contains('250 Directory deleted'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output, contains('250 Directory deleted'));
      }
      expect(output, isNot(contains('test_dir')));
      expect(Directory('${allowedDirectories.first}/test_dir').existsSync(),
          isFalse);
    });

    test('$testDescription: Store File', () async {
      final testFile = File('${allowedDirectories.first}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('put test_file.txt'); // Use relative path
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output =
            await execFTPCmdOnWin("put test_file.txt"); // Use relative path
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(output, contains('test_file.txt'));
    });

    test('$testDescription: Retrieve File', () async {
      final testPath = 'test_file_ret.txt'; // Relative path
      final testFile = File('${allowedDirectories.first}/$testPath')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin
          .writeln('get test_file_ret.txt test_file_ret.txt'); // Relative paths
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            'get test_file_ret.txt test_file_ret.txt'); // Relative paths
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin('dir');
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(
          File('${allowedDirectories.first}/$testPath').existsSync(), isTrue);
      if (File('./test_file_ret.txt').existsSync()) {
        File('./test_file_ret.txt').deleteSync();
      }
    });

    test('$testDescription: Delete File', () async {
      final testFile = File('${allowedDirectories.first}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('delete test_file.txt'); // Use relative path
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = (await execFTPCmdOnWin(
            'delete test_file.txt')); // Use relative path
        expect(output, contains('250 File deleted'));
        output = (await execFTPCmdOnWin('dir'));
      } else {
        expect(output, contains('250 File deleted'));
      }
      expect(output, isNot(contains('test_file.txt')));
      expect(testFile.existsSync(), isFalse);
    });

    test('$testDescription: Handle Special Characters in Filenames', () async {
      final testFile =
          File('${allowedDirectories.first}/test_file_!@#\$%^&*().txt')
            ..writeAsStringSync('Special characters in the filename');
      ftpClient.stdin
          .writeln('put test_file_!@#\$%^&*().txt'); // Use relative path
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "put test_file_!@#\$%^&*().txt"); // Use relative path
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(output, contains('test_file_!@#\$%^&*().txt'));
    });

    test('$testDescription: Handle Large File Transfer', () async {
      final largeFile = File('${allowedDirectories.first}/large_file.txt')
        ..writeAsBytesSync(List.generate(
            1024 * 1024 * 50, (index) => index % 256)); // 50MB file
      ftpClient.stdin.writeln('put large_file.txt'); // Use relative path
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output =
            await execFTPCmdOnWin("put large_file.txt"); // Use relative path
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(output, contains('large_file.txt'));
    });

    test('$testDescription: Handle Directory with Special Characters',
        () async {
      ftpClient.stdin.writeln('mkdir special!@#\$%^&*()_dir');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("mkdir special!@#\$%^&*()_dir\nls");
      } else {
        expect(output, contains('257 "special!@#\$%^&*()_dir" created'));
      }
      expect(output, contains('special!@#\$%^&*()_dir'));
    });

    test('$testDescription: File Size', () async {
      final testFile = File('${allowedDirectories.first}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('size test_file.txt'); // Use relative path
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output =
            await execFTPCmdOnWin("size test_file.txt"); // Use relative path
      }

      String expectedSizeOutput = outputHandler.getExpectedSizeOutput(11);
      expect(output, contains(expectedSizeOutput));
    });

    test('$testDescription: Prevent Navigation Above Root Directory', () async {
      ftpClient.stdin.writeln('cd ..');
      ftpClient.stdin.writeln('cd ..');
      ftpClient.stdin.writeln('cd ..');
      ftpClient.stdin.writeln('cd ..');
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin('cd ..\npwd');
      }

      final expectedOutput = outputHandler.getExpectedPwdOutput('/');
      expect(output, contains(expectedOutput));
    });

    if (!Platform.isWindows) {
      test('$testDescription: System Command', () async {
        ftpClient.stdin.writeln('syst');
        ftpClient.stdin.writeln('quit');
        await ftpClient.stdin.flush();

        var output = await readAllOutput(logFilePath);

        expect(output, contains('215 UNIX Type: L8'));
      });
    }

    test('$testDescription: Print Working Directory Command', () async {
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin('pwd');
      }

      final expectText = outputHandler.getExpectedPwdOutput('/');
      expect(output, contains(expectText));
    });

    test('$testDescription: List Nested Directories', () async {
      final nestedDirPath = '${allowedDirectories.first}/outer_dir/inner_dir';
      Directory(nestedDirPath).createSync(recursive: true);

      ftpClient.stdin.writeln('cd outer_dir'); // Use relative path
      ftpClient.stdin.writeln('pwd');

      ftpClient.stdin.writeln('ls');

      ftpClient.stdin.writeln('cd inner_dir');
      ftpClient.stdin.writeln('pwd');

      ftpClient.stdin.writeln('ls');

      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            'cd outer_dir\npwd\nls\ncd inner_dir\npwd\nls'); // Use relative paths
      }

      final expectedOuterDir = '/outer_dir';
      final expectedInnerDir = '/outer_dir/inner_dir';

      expect(
          output,
          contains(outputHandler
              .getExpectedDirectoryChangeOutput(expectedOuterDir)));
      expect(
          output,
          contains(outputHandler
              .getExpectedDirectoryChangeOutput(expectedInnerDir)));
      expect(output, contains('inner_dir'));
    });

    test(
        '$testDescription: Change Directories Using Absolute and Relative Paths',
        () async {
      final nestedDirPath = '${allowedDirectories.first}/outer_dir/inner_dir';
      Directory(nestedDirPath).createSync(recursive: true);

      ftpClient.stdin.writeln('cd outer_dir'); // Use relative path
      ftpClient.stdin.writeln('pwd');

      ftpClient.stdin.writeln('cd inner_dir');
      ftpClient.stdin.writeln('pwd');

      ftpClient.stdin.writeln('cd ..');
      ftpClient.stdin.writeln('pwd');

      ftpClient.stdin.writeln('cd $nestedDirPath'); // Absolute path
      ftpClient.stdin.writeln('pwd');

      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            'cd outer_dir\npwd\ncd inner_dir\npwd\ncd ..\npwd\ncd $nestedDirPath\npwd');
      }

      final expectedOuterDir = '/outer_dir';
      final expectedInnerDir = '/outer_dir/inner_dir';

      expect(
          output,
          contains(outputHandler
              .getExpectedDirectoryChangeOutput(expectedOuterDir)));
      expect(
          output,
          contains(outputHandler
              .getExpectedDirectoryChangeOutput(expectedInnerDir)));
      expect(
          output,
          contains(outputHandler
              .getExpectedDirectoryChangeOutput(expectedOuterDir)));
      expect(
          output,
          contains(outputHandler
              .getExpectedDirectoryChangeOutput(expectedInnerDir)));
    });

    test('$testDescription: Handle Large File Transfer', () async {
      // Create a 1 GB file
      final largeFile = File('${allowedDirectories.first}/large_file.txt')
        ..writeAsBytesSync(List.generate(
            1024 * 1024 * 1024, (index) => index % 256)); // 1GB file
      ftpClient.stdin.writeln('put large_file.txt'); // Use relative path
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output =
            await execFTPCmdOnWin("put large_file.txt"); // Use relative path
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(output, contains('large_file.txt'));
    });
  }

  group('FTP Server Tests with PhysicalFileOperations', () {
    final Directory tempDir1 = Directory.systemTemp.createTempSync('ftp_test1');
    runTestsForFileOperations(
      'PhysicalFileOperations',
      PhysicalFileOperations(tempDir1.path),
      [tempDir1.path],
    );
  });

  group('FTP Server Tests with VirtualFileOperations', () {
    final Directory tempDir1 = Directory.systemTemp.createTempSync('ftp_test2');
    final Directory tempDir2 = Directory.systemTemp.createTempSync('ftp_test3');
    runTestsForFileOperations(
      'VirtualFileOperations',
      VirtualFileOperations([tempDir1.path, tempDir2.path]),
      [tempDir1.path, tempDir2.path],
    );
  });
}
