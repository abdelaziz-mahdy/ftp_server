// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';
import 'platform_output_handler/platform_output_handler_factory.dart';
import 'platform_output_handler/platform_output_handler.dart';

void main() {
  final PlatformOutputHandler outputHandler =
      PlatformOutputHandlerFactory.create();
  const int port = 2126;
  final Directory tempDir1 = Directory.systemTemp.createTempSync('ftp_test2');
  final Directory tempDir2 = Directory.systemTemp.createTempSync('ftp_test3');
  List<String> sharedDirectories = [tempDir1.path, tempDir2.path];
  final Directory clientTempDir =
      Directory.systemTemp.createTempSync('ftp_test0');

  Future<String> execFTPCmdOnWin(String commands) async {
    const String ftpHost = '127.0.0.1 $port';
    const String user = 'test';
    const String password = 'password';

    String fullCommands = '''
    open $ftpHost
    user $user $password
    $commands
    quit
    ''';
    // this to avoid conflicting commands
    int randomNumber = Random().nextInt(100000);
    String fileName = 'ftp_win_script_$randomNumber.txt';
    File scriptFile = File(fileName);
    await scriptFile.writeAsString(fullCommands);

    try {
      ProcessResult result = await Process.run(
        'ftp',
        ['-n', '-v', '-s:$fileName'],
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
        const Duration(milliseconds: 500)); // Wait for log to be written
    return File(logFilePath).readAsStringSync();
  }

  late FtpServer server;
  late Process ftpClient;
  final String logFilePath = '${sharedDirectories.first}/ftpsession.log';

  group('FTP Server Read and Write Mode', () {
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
        sharedDirectories: sharedDirectories,
        startingDirectory: basename(sharedDirectories.first),
        serverType: ServerType.readAndWrite,
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

    test('Authentication Success', () async {
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("quit");
      }

      expect(output, contains('230 User logged in, proceed'));
    });

    test('List Directory', () async {
      ftpClient.stdin.writeln('cd ..');
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
        output = await execFTPCmdOnWin("cd ..\n ls");
      }

      String listing = await outputHandler.generateDirectoryListing(
          '/', VirtualFileOperations(sharedDirectories));

      String normalizedOutput = outputHandler.normalizeDirectoryListing(output);
      String normalizedExpected =
          outputHandler.normalizeDirectoryListing(listing);

      expect(normalizedOutput, contains(normalizedExpected));
    });

    test('Change Directory', () async {
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('cd /');
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

    test('Make Directory', () async {
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
      expect(Directory('${sharedDirectories.first}/test_dir').existsSync(),
          isTrue);
    });

    test('Remove Directory', () async {
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('rmdir test_dir');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("mkdir test_dir\nrmdir test_dir\nls\n");
        expect(output, contains('250 Directory deleted'));
      } else {
        expect(output, contains('250 Directory deleted'));
      }
      expect(output, (contains('test_dir')));
      expect(Directory('${sharedDirectories.first}/test_dir').existsSync(),
          isFalse);
    });

    test('Store File', () async {
      var filename = 'test_file.txt';
      final testFile = File('${clientTempDir.path}/$filename')
        ..writeAsStringSync('Hello, FTP!');

      ftpClient.stdin.writeln('put ${testFile.path} $filename');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("put ${testFile.path} $filename");
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(output, contains(filename));
    });

    test('Retrieve File', () async {
      const testPath = 'test_file_ret.txt';
      File('${sharedDirectories.first}/$testPath')
          .writeAsStringSync('Hello, FTP!');
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('get test_file_ret.txt test_file_ret.txt');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output =
            await execFTPCmdOnWin('get test_file_ret.txt test_file_ret.txt');
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin('dir');
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(File('${sharedDirectories.first}/$testPath').existsSync(), isTrue);
      if (File('./test_file_ret.txt').existsSync()) {
        File('./test_file_ret.txt').deleteSync();
      }
    });

    test('Delete File', () async {
      final testFile = File('${sharedDirectories.first}/test_file.txt')
        ..writeAsStringSync('Hello, FTP!');
      ftpClient.stdin.writeln('delete test_file.txt');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin('delete test_file.txt');
        expect(output, contains('250 File deleted'));
        output = await execFTPCmdOnWin('dir');
      } else {
        expect(output, contains('250 File deleted'));
      }
      expect(output, isNot(contains('test_file.txt')));
      expect(testFile.existsSync(), isFalse);
    });
    if (!Platform.isWindows) {
      test('Handle Special Characters in Filenames', () async {
        String filename = "test_file_!@#\$%^&*().txt";
        final testFile = File('${clientTempDir.path}/$filename')
          ..writeAsStringSync('Special characters in the filename');
        ftpClient.stdin.writeln('put ${testFile.path} $filename');
        ftpClient.stdin.writeln('ls');
        ftpClient.stdin.writeln('quit');
        await ftpClient.stdin.flush();

        var output = await readAllOutput(logFilePath);
        if (Platform.isWindows) {
          output = await execFTPCmdOnWin("put ${testFile.path} $filename");
          expect(output, contains('226 Transfer complete'));
          output = await execFTPCmdOnWin("ls");
        } else {
          expect(output, contains('226 Transfer complete'));
        }
        expect(output, contains(filename));
      });
    }

    test('Handle Large File Transfer', () async {
      var filename = "large_file_10M.txt";
      final testFile = File('${clientTempDir.path}/$filename')
        ..writeAsBytesSync(
            List.generate(1024 * 1024 * 10, (index) => index % 256));
      ftpClient.stdin.writeln('put ${testFile.path} $filename');
      await Future.delayed(const Duration(seconds: 2));
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("put ${testFile.path} $filename");
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(output, contains(filename));
    });

    test('Handle Directory with Special Characters', () async {
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
    if (!Platform.isWindows) {
      test('File Size', () async {
        File('${sharedDirectories.first}/test_file.txt')
            .writeAsStringSync('Hello, FTP!');
        ftpClient.stdin.writeln('size test_file.txt');
        ftpClient.stdin.writeln('quit');
        await ftpClient.stdin.flush();

        var output = await readAllOutput(logFilePath);
        if (Platform.isWindows) {
          output = await execFTPCmdOnWin("size test_file.txt");
        }

        String expectedSizeOutput = outputHandler.getExpectedSizeOutput(11);
        expect(output, contains(expectedSizeOutput));
      });
    }

    test('Prevent Navigation Above Root Directory', () async {
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
      test('System Command', () async {
        ftpClient.stdin.writeln('syst');
        ftpClient.stdin.writeln('quit');
        await ftpClient.stdin.flush();

        var output = await readAllOutput(logFilePath);

        expect(output, contains('215 UNIX Type: L8'));
      });
    }

    test('Print Working Directory Command', () async {
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin('pwd');
      }

      final expectText = outputHandler
          .getExpectedPwdOutput('/${basename(sharedDirectories.first)}');
      expect(output, contains(expectText));
    });

    test('List Nested Directories', () async {
      final nestedDirPath = '${sharedDirectories.first}/outer_dir/inner_dir';
      Directory(nestedDirPath).createSync(recursive: true);

      ftpClient.stdin.writeln('cd outer_dir');
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
            'cd outer_dir\npwd\nls\ncd inner_dir\npwd\nls');
      }

      final expectedOuterDir =
          '/${basename(sharedDirectories.first)}/outer_dir';
      final expectedInnerDir =
          '/${basename(sharedDirectories.first)}/outer_dir/inner_dir';

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

    test('Change Directories Using Absolute and Relative Paths', () async {
      final nestedDirPath = '${sharedDirectories.first}/outer_dir/inner_dir';
      Directory(nestedDirPath).createSync(recursive: true);

      ftpClient.stdin.writeln('cd outer_dir');
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('cd inner_dir');
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('cd ..');
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('cd ${basename(nestedDirPath)}');
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            'cd outer_dir\npwd\ncd inner_dir\npwd\ncd ..\npwd\ncd ${basename(nestedDirPath)}\npwd');
      }

      var expectedOuterDir = '/${basename(sharedDirectories.first)}/outer_dir';
      var expectedInnerDir =
          '/${basename(sharedDirectories.first)}/outer_dir/inner_dir';

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

    test('Handle Large File Transfer', () async {
      String filename = "large_file_50M.txt";
      final testFile = File('${clientTempDir.path}/$filename')
        ..writeAsBytesSync(
            List.generate(1024 * 1024 * 50, (index) => index % 256));
      ftpClient.stdin.writeln('put ${testFile.path} $filename');
      await Future.delayed(const Duration(seconds: 5));
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("put ${testFile.path} $filename");
        expect(output, contains('226 Transfer complete'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output, contains('226 Transfer complete'));
      }
      expect(output, contains(filename));
    });
  });

  group('FTP Server Read-Only Mode', () {
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
        sharedDirectories: sharedDirectories,
        startingDirectory: sharedDirectories.first,
        serverType: ServerType.readOnly,
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

    test('Prevent Write Operation', () async {
      var filename = 'test_file.txt';
      ftpClient.stdin.writeln('put ${clientTempDir.path}/$filename $filename');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "put ${clientTempDir.path}/$filename $filename");
        expect(output, contains('550 Command not allowed in read-only mode'));
      } else {
        expect(output, contains('550 Command not allowed in read-only mode'));
      }
    });

    test('Prevent Delete Operation', () async {
      ftpClient.stdin.writeln('delete test_file.txt');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("delete test_file.txt");
        expect(output, contains('550 Command not allowed in read-only mode'));
      } else {
        expect(output, contains('550 Command not allowed in read-only mode'));
      }
    });

    test('Prevent Make Directory', () async {
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("mkdir test_dir");
        expect(output, contains('550 Command not allowed in read-only mode'));
      } else {
        expect(output, contains('550 Command not allowed in read-only mode'));
      }
    });
  });

  group('FTP Server Without Authentication', () {
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
        sharedDirectories: sharedDirectories,
        startingDirectory: basename(sharedDirectories.first),
        serverType: ServerType.readAndWrite,
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

    test('Connect Without Authentication', () async {
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("quit");
      }

      expect(output, contains('230 User logged in, proceed'));
    });

    test('Perform Operations Without Authentication', () async {
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('mkdir test_no_auth_dir');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("ls\nmkdir test_no_auth_dir\nls");
      }

      expect(output, contains('257 "test_no_auth_dir" created'));
      expect(output, contains('test_no_auth_dir'));
    });
  });

  group('Server handles multiple clients simultaneously', () {
    final int numClients = 5;
    final List<Process> ftpClients = [];
    final List<String> logFilePaths = [];

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
        sharedDirectories: sharedDirectories,
        startingDirectory: basename(sharedDirectories.first),
        serverType: ServerType.readAndWrite,
        logFunction: (String message) => print(message),
      );
      await server.startInBackground();
      for (int i = 0; i < numClients; i++) {
        final logFilePath =
            '${sharedDirectories.first}/ftpsession_client_$i.log';
        logFilePaths.add(logFilePath);

        // Start the FTP clients
        ftpClients.add(await Process.start(
          Platform.isWindows ? 'ftp' : 'bash',
          Platform.isWindows ? ['-n', '-v'] : ['-c', 'ftp -n -v'],
          runInShell: true,
        ));

        // Authenticate the clients
        await connectAndAuthenticate(ftpClients[i], logFilePath);
      }
    });

    tearDownAll(() async {
      // Clean up each client and its resources
      for (var i = 0; i < numClients; i++) {
        ftpClients[i].kill(); // Kill the client process
      }

      // Delete the logs created during the test
      for (var logPath in logFilePaths) {
        if (File(logPath).existsSync()) {
          File(logPath).deleteSync();
        }
      }
      server.stop();
    });

    test('Multiple clients execute commands simultaneously', () async {
      final List<Future<void>> clientTasks = [];

      for (int i = 0; i < numClients; i++) {
        clientTasks.add(Future<void>(() async {
          // Client-specific directory
          final dirName = 'test_dir_client_$i';

          if (Platform.isWindows) {
            // Windows-specific commands
            var output =
                await execFTPCmdOnWin('mkdir $dirName\nls\nrmdir $dirName\nls');

            // Check directory creation
            expect(output, contains('257 "$dirName" created'));

            // Check directory listing contains the newly created directory
            expect(output, contains(dirName));

            // Check directory deletion
            expect(output, contains('250 Directory deleted'));

            // Check directory listing after deletion
            expect(output, contains(dirName));
          } else {
            // Non-Windows (Linux/Mac) commands
            ftpClients[i].stdin.writeln('mkdir $dirName');
            ftpClients[i].stdin.writeln('ls');
            ftpClients[i].stdin.writeln('rmdir $dirName');
            ftpClients[i].stdin.writeln('ls');
            ftpClients[i].stdin.writeln('quit');
            await ftpClients[i].stdin.flush();

            // Check the output for client `i`
            var output = await readAllOutput(logFilePaths[i]);

            // Check directory creation
            expect(output, contains('257 "$dirName" created'));

            // Check directory listing contains the newly created directory
            expect(output, contains(dirName));

            // Check directory deletion
            expect(output, contains('250 Directory deleted'));

            // Check directory listing after deletion
            expect(output, contains(dirName));
          }
        }));
      }

      // Run all client tasks in parallel
      await Future.wait(clientTasks);
    });
  });
  group('Server termination', () {
    test(
        'Close method terminates active sessions and clears activeSessions list',
        () async {
      server = FtpServer(
        port,
        username: 'test',
        password: 'password',
        sharedDirectories: sharedDirectories,
        startingDirectory: basename(sharedDirectories.first),
        serverType: ServerType.readAndWrite,
        logFunction: (String message) => print(message),
      );
      await server.startInBackground();
      // Create a test client and connect to the server
      ftpClient = await Process.start(
        Platform.isWindows ? 'ftp' : 'bash',
        Platform.isWindows ? ['-n', '-v'] : ['-c', 'ftp -n -v'],
        runInShell: true,
      );
      if (Platform.isWindows) {
        await execFTPCmdOnWin('pwd');
      } else {
        // Authenticate the test client
        await connectAndAuthenticate(ftpClient, logFilePath);
      }
      await Future.delayed(
          const Duration(milliseconds: 500)); // Wait for log to be written
      // Ensure there's an active session
      expect(server.activeSessions.isNotEmpty, isTrue,
          reason: 'No active sessions found after client connected');

      // Call the stop method
      await server.stop();
      // Verify that all active sessions are terminated
      expect(server.activeSessions.isEmpty, isTrue,
          reason: 'Active sessions list is not cleared after server stop');
    });
  });
}
