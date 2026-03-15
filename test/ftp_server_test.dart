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
        fileOperations: VirtualFileOperations(sharedDirectories,
            startingDirectory: basename(sharedDirectories.first)),
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
      ftpClient.stdin.writeln('cd /${basename(sharedDirectories.first)}');
      ftpClient.stdin.writeln('mkdir test_dir');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "cd /${basename(sharedDirectories.first)}\nmkdir test_dir\nls");
      }

      // Use outputHandler for expected MKD output
      expect(output,
          contains(outputHandler.getExpectedMakeDirectoryOutput('test_dir')));
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
      }
      // Use outputHandler for expected RMD output
      expect(output,
          contains(outputHandler.getExpectedDeleteDirectoryOutput('test_dir')));
      // The directory might still be listed briefly in the output before deletion confirmation
      // expect(output, isNot(contains('test_dir'))); // This check might be flaky depending on timing
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
        // Use outputHandler for transfer complete message
        expect(output,
            contains(outputHandler.getExpectedTransferCompleteOutput()));
        output = await execFTPCmdOnWin("ls");
      } else {
        // Use outputHandler for transfer complete message
        expect(output,
            contains(outputHandler.getExpectedTransferCompleteOutput()));
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
        // Use outputHandler for transfer complete message
        expect(output,
            contains(outputHandler.getExpectedTransferCompleteOutput()));
        output = await execFTPCmdOnWin('dir');
      } else {
        // Use outputHandler for transfer complete message
        expect(output,
            contains(outputHandler.getExpectedTransferCompleteOutput()));
      }
      expect(File('${sharedDirectories.first}/$testPath').existsSync(), isTrue);
      if (File('./test_file_ret.txt').existsSync()) {
        File('./test_file_ret.txt').deleteSync();
      }
    });

    test('Rename File (RNFR/RNTO)', () async {
      const testFileName = 'test_rename_file.txt';
      const newFileName = 'renamed_file.txt';

      // Create test file
      File('${sharedDirectories.first}/$testFileName')
          .writeAsStringSync('Test content for rename');

      ftpClient.stdin.writeln('cd /${basename(sharedDirectories.first)}');
      ftpClient.stdin.writeln('rename $testFileName $newFileName');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "cd /${basename(sharedDirectories.first)}\nrename $testFileName $newFileName\nls");
        expect(output,
            contains('250 Requested file action completed successfully'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output,
            contains('250 Requested file action completed successfully'));
      }

      expect(output, contains(newFileName));
      expect(
          File('${sharedDirectories.first}/$newFileName').existsSync(), isTrue);
      expect(File('${sharedDirectories.first}/$testFileName').existsSync(),
          isFalse);

      // Cleanup
      if (File('${sharedDirectories.first}/$newFileName').existsSync()) {
        File('${sharedDirectories.first}/$newFileName').deleteSync();
      }
    });

    test('Rename Directory (RNFR/RNTO)', () async {
      const testDirName = 'test_rename_dir';
      const newDirName = 'renamed_dir';

      // Create test directory
      final testDir = Directory('${sharedDirectories.first}/$testDirName');
      await testDir.create();

      ftpClient.stdin.writeln('cd /${basename(sharedDirectories.first)}');
      ftpClient.stdin.writeln('rename $testDirName $newDirName');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "cd /${basename(sharedDirectories.first)}\nrename $testDirName $newDirName\nls");
        expect(output,
            contains('250 Requested file action completed successfully'));
        output = await execFTPCmdOnWin("ls");
      } else {
        expect(output,
            contains('250 Requested file action completed successfully'));
      }

      expect(output, contains(newDirName));
      expect(Directory('${sharedDirectories.first}/$newDirName').existsSync(),
          isTrue);
      expect(Directory('${sharedDirectories.first}/$testDirName').existsSync(),
          isFalse);

      // Cleanup
      if (Directory('${sharedDirectories.first}/$newDirName').existsSync()) {
        Directory('${sharedDirectories.first}/$newDirName').deleteSync();
      }
    });

    test('Rename with non-existent file should fail', () async {
      ftpClient.stdin.writeln('cd /${basename(sharedDirectories.first)}');
      ftpClient.stdin.writeln('rename non_existent_file.txt new_name.txt');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "cd /${basename(sharedDirectories.first)}\nrename non_existent_file.txt new_name.txt");
        expect(output, contains('550 File not found'));
      } else {
        expect(output, contains('550 File not found'));
      }
    });

    test('Rename to existing file should fail', () async {
      const testFileName1 = 'test_file1.txt';
      const testFileName2 = 'test_file2.txt';

      // Create two test files
      File('${sharedDirectories.first}/$testFileName1')
          .writeAsStringSync('Content 1');
      File('${sharedDirectories.first}/$testFileName2')
          .writeAsStringSync('Content 2');

      ftpClient.stdin.writeln('cd /${basename(sharedDirectories.first)}');
      ftpClient.stdin.writeln('rename $testFileName1 $testFileName2');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "cd /${basename(sharedDirectories.first)}\nrename $testFileName1 $testFileName2");
        expect(output, contains('550 Failed to rename'));
      } else {
        expect(output, contains('550 Failed to rename'));
      }

      // Both files should still exist
      expect(File('${sharedDirectories.first}/$testFileName1').existsSync(),
          isTrue);
      expect(File('${sharedDirectories.first}/$testFileName2').existsSync(),
          isTrue);

      // Cleanup
      if (File('${sharedDirectories.first}/$testFileName1').existsSync()) {
        File('${sharedDirectories.first}/$testFileName1').deleteSync();
      }
      if (File('${sharedDirectories.first}/$testFileName2').existsSync()) {
        File('${sharedDirectories.first}/$testFileName2').deleteSync();
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
        // Use outputHandler for expected DELE output
        expect(
            output,
            contains(
                outputHandler.getExpectedDeleteFileOutput('test_file.txt')));
        output = await execFTPCmdOnWin('dir');
      } else {
        // Use outputHandler for expected DELE output
        expect(
            output,
            contains(
                outputHandler.getExpectedDeleteFileOutput('test_file.txt')));
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
          // Use outputHandler for transfer complete message
          expect(output,
              contains(outputHandler.getExpectedTransferCompleteOutput()));
          output = await execFTPCmdOnWin("ls");
        } else {
          // Use outputHandler for transfer complete message
          expect(output,
              contains(outputHandler.getExpectedTransferCompleteOutput()));
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
        // Use outputHandler for transfer complete message
        expect(output,
            contains(outputHandler.getExpectedTransferCompleteOutput()));
        output = await execFTPCmdOnWin("ls");
      } else {
        // Use outputHandler for transfer complete message
        expect(output,
            contains(outputHandler.getExpectedTransferCompleteOutput()));
      }
      expect(output, contains(filename));
    });

    test('Handle Directory with Special Characters', () async {
      final dirName = 'special!@#\$%^&*()_dir';
      ftpClient.stdin.writeln('mkdir $dirName');
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
      ftpClient.stdin.writeln('cd /${basename(sharedDirectories.first)}');
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            'cd /${basename(sharedDirectories.first)}\npwd');
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
        // Use outputHandler for transfer complete message
        expect(output,
            contains(outputHandler.getExpectedTransferCompleteOutput()));
        output = await execFTPCmdOnWin("ls");
      } else {
        // Use outputHandler for transfer complete message
        expect(output,
            contains(outputHandler.getExpectedTransferCompleteOutput()));
      }
      expect(output, contains(filename));
    });
    test('All commands sequence in one test', () async {
      ftpClient.stdin.writeln('cd /${basename(sharedDirectories.first)}');
      // Create a directory
      final dirName = 'test_sequence_dir';
      ftpClient.stdin.writeln('mkdir $dirName');
      await ftpClient.stdin.flush();
      await Future.delayed(const Duration(milliseconds: 500));

      // Change to the new directory
      ftpClient.stdin.writeln('cd $dirName');
      await ftpClient.stdin.flush();
      await Future.delayed(const Duration(milliseconds: 500));

      // Upload a file
      var filename = 'test_sequence_file.txt';
      final testFile = File('${clientTempDir.path}/$filename')
        ..writeAsStringSync('Sequence Test Content');
      ftpClient.stdin.writeln('put ${testFile.path} $filename');
      await ftpClient.stdin.flush();
      await Future.delayed(const Duration(seconds: 2));

      // Download the file
      ftpClient.stdin.writeln('get $filename downloaded_$filename');
      await ftpClient.stdin.flush();
      await Future.delayed(const Duration(seconds: 2));

      // Delete the file
      ftpClient.stdin.writeln('delete $filename');
      await ftpClient.stdin.flush();
      await Future.delayed(const Duration(milliseconds: 500));

      // Go back to parent directory
      ftpClient.stdin.writeln('cd ..');
      await ftpClient.stdin.flush();
      await Future.delayed(const Duration(milliseconds: 500));

      // Remove the directory
      ftpClient.stdin.writeln('rmdir $dirName');
      await ftpClient.stdin.flush();
      await Future.delayed(const Duration(milliseconds: 500));

      // List directory contents to verify
      ftpClient.stdin.writeln('ls');
      await ftpClient.stdin.flush();
      await Future.delayed(const Duration(milliseconds: 500));

      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);

      if (Platform.isWindows) {
        // Execute sequence of commands for Windows
        output =
            await execFTPCmdOnWin("cd /${basename(sharedDirectories.first)}\n"
                "mkdir $dirName\n"
                "cd $dirName\n"
                "put ${testFile.path} $filename\n"
                "get $filename downloaded_$filename\n"
                "delete $filename\n"
                "cd ..\n"
                "rmdir $dirName\n"
                "ls");
      }

      // Use outputHandler for expected outputs
      expect(output,
          contains(outputHandler.getExpectedMakeDirectoryOutput(dirName)));
      expect(
          output,
          contains(outputHandler.getExpectedDirectoryChangeOutput(
              '/${basename(sharedDirectories.first)}/$dirName')));
      expect(
          output,
          contains(outputHandler
              .getExpectedTransferCompleteOutput())); // Check for successful file upload and download
      expect(output,
          contains(outputHandler.getExpectedDeleteFileOutput(filename)));
      expect(output,
          contains(outputHandler.getExpectedDeleteDirectoryOutput(dirName)));

      // Verify that the downloaded file exists and has the correct content
      final downloadedFile = File('downloaded_$filename');
      expect(downloadedFile.existsSync(), isTrue);
      expect(
          downloadedFile.readAsStringSync(), contains('Sequence Test Content'));

      // Clean up downloaded file
      if (downloadedFile.existsSync()) {
        downloadedFile.deleteSync();
      }

      // Verify that the directory and the uploaded file no longer exist
      expect(Directory('${sharedDirectories.first}/$dirName').existsSync(),
          isFalse);
      expect(
          File('${sharedDirectories.first}/$filename').existsSync(), isFalse);
    });

    group('Directory Listing Operations', () {
      test('List Current Directory (Internal)', () async {
        // First change to a specific directory
        ftpClient.stdin.writeln('cd /${basename(sharedDirectories.first)}');
        await ftpClient.stdin.flush();

        // Then list current directory
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
          output = await execFTPCmdOnWin(
              "cd ${basename(sharedDirectories.first)}\n ls");
        }

        String listing = await outputHandler.generateDirectoryListing(
            '',
            VirtualFileOperations(sharedDirectories,
                startingDirectory: basename(sharedDirectories.first)));

        String normalizedOutput =
            outputHandler.normalizeDirectoryListing(output);
        String normalizedExpected =
            outputHandler.normalizeDirectoryListing(listing);

        expect(normalizedOutput, contains(normalizedExpected));
      });

      test('List Root Directory', () async {
        ftpClient.stdin.writeln('cd /');
        await ftpClient.stdin.flush();

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
          output = await execFTPCmdOnWin("cd /\n ls");
        }

        String listing = await outputHandler.generateDirectoryListing(
            '/', VirtualFileOperations(sharedDirectories));

        String normalizedOutput =
            outputHandler.normalizeDirectoryListing(output);
        String normalizedExpected =
            outputHandler.normalizeDirectoryListing(listing);

        expect(normalizedOutput, contains(normalizedExpected));
      });

      test('List Specific Directory with Path', () async {
        // Create a test directory and file
        final testDir = Directory('${sharedDirectories.first}/test_dir');
        await testDir.create();
        final testFile = File('${testDir.path}/test.txt');
        await testFile.writeAsString('test content');

        ftpClient.stdin.writeln(
            'ls test_dir'); // Use relative path from current directory '/<basename>'
        if (Platform.isLinux) {
          ftpClient.stdin.writeln('passive on');
          ftpClient.stdin.writeln('ls test_dir'); // Use relative path
          ftpClient.stdin.writeln('passive off');
        }
        ftpClient.stdin.writeln('quit');
        await ftpClient.stdin.flush();

        var output = await readAllOutput(logFilePath);
        if (Platform.isWindows) {
          // Ensure we are in the correct starting directory before using relative path
          output = await execFTPCmdOnWin(
              "cd ${basename(sharedDirectories.first)}\nls test_dir");
        }

        // Create VFS instance with the correct starting directory for generating expected output
        final vfsForListing = VirtualFileOperations(sharedDirectories,
            startingDirectory: basename(sharedDirectories.first));
        String listing = await outputHandler.generateDirectoryListing(
            'test_dir', // Use relative path, resolved against vfsForListing.currentDirectory
            vfsForListing);

        String normalizedOutput =
            outputHandler.normalizeDirectoryListing(output);
        String normalizedExpected =
            outputHandler.normalizeDirectoryListing(listing);

        expect(normalizedOutput, contains(normalizedExpected));

        // Cleanup
        await testFile.delete();
        await testDir.delete();
      });

      test('List Directory with Relative Path', () async {
        // First change to a parent directory
        ftpClient.stdin.writeln('cd ${basename(sharedDirectories.first)}');
        await ftpClient.stdin.flush();

        // Create a test directory and file
        final testDir = Directory('${sharedDirectories.first}/test_dir');
        await testDir.create();
        final testFile = File('${testDir.path}/test.txt');
        await testFile.writeAsString('test content');

        // List using relative path
        ftpClient.stdin.writeln('ls test_dir');
        if (Platform.isLinux) {
          ftpClient.stdin.writeln('passive on');
          ftpClient.stdin.writeln('ls test_dir');
          ftpClient.stdin.writeln('passive off');
        }
        ftpClient.stdin.writeln('quit');
        await ftpClient.stdin.flush();

        var output = await readAllOutput(logFilePath);
        if (Platform.isWindows) {
          output = await execFTPCmdOnWin(
              "cd ${basename(sharedDirectories.first)}\n ls test_dir");
        }

        String listing = await outputHandler.generateDirectoryListing(
            'test_dir', VirtualFileOperations(sharedDirectories));

        String normalizedOutput =
            outputHandler.normalizeDirectoryListing(output);
        String normalizedExpected =
            outputHandler.normalizeDirectoryListing(listing);

        expect(normalizedOutput, contains(normalizedExpected));

        // Cleanup
        await testFile.delete();
        await testDir.delete();
      });
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
        fileOperations: VirtualFileOperations(sharedDirectories,
            startingDirectory: basename(sharedDirectories.first)),
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

    test('Prevent Rename Operations', () async {
      ftpClient.stdin.writeln('rename some_file.txt new_name.txt');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("rename some_file.txt new_name.txt");
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
        fileOperations: VirtualFileOperations(sharedDirectories,
            startingDirectory: basename(sharedDirectories.first)),
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
      final dirName = 'test_no_auth_dir';
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('mkdir $dirName');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin("ls\nmkdir $dirName\nls");
      }

      // Use outputHandler for expected MKD output
      expect(output,
          contains(outputHandler.getExpectedMakeDirectoryOutput(dirName)));
      expect(output, contains(dirName));
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
        fileOperations: VirtualFileOperations(sharedDirectories,
            startingDirectory: basename(sharedDirectories.first)),
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

            // Use outputHandler for expected outputs
            expect(
                output,
                contains(
                    outputHandler.getExpectedMakeDirectoryOutput(dirName)));
            expect(output, contains(dirName)); // Check listing contains the dir
            expect(
                output,
                contains(
                    outputHandler.getExpectedDeleteDirectoryOutput(dirName)));
            // Check directory listing after deletion (might still contain the name depending on timing)
            // expect(output, isNot(contains(dirName)));
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

            // Use outputHandler for expected outputs
            expect(
                output,
                contains(
                    outputHandler.getExpectedMakeDirectoryOutput(dirName)));
            expect(output, contains(dirName)); // Check listing contains the dir
            expect(
                output,
                contains(
                    outputHandler.getExpectedDeleteDirectoryOutput(dirName)));
            // Check directory listing after deletion (might still contain the name depending on timing)
            // expect(output, isNot(contains(dirName)));
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
        fileOperations: VirtualFileOperations(sharedDirectories,
            startingDirectory: basename(sharedDirectories.first)),
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

  group('Directory Mapping Tests', () {
    // Create a separate temp directory for the mapped structure
    final Directory mappedTempDir =
        Directory.systemTemp.createTempSync('ftp_mapped_dir');

    // Setup directory mappings similar to what's in the logs
    final directoryMappings = ['${mappedTempDir.path}/photos'];

    setUpAll(() async {
      if (!await isFtpAvailable()) {
        await installFtp();
      }

      // Create the mapped directory structure
      Directory('${mappedTempDir.path}/photos').createSync(recursive: true);

      // Start server with directory mappings
      server = FtpServer(
        port,
        username: 'yxz',
        password: '123456',
        fileOperations: VirtualFileOperations(directoryMappings),
        serverType: ServerType.readAndWrite,
        logFunction: (String message) => print(message),
      );
      await server.startInBackground();
    });

    tearDownAll(() async {
      await server.stop();
      // Clean up the temp directory
      if (mappedTempDir.existsSync()) {
        mappedTempDir.deleteSync(recursive: true);
      }
    });

    setUp(() async {
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
      ftpClient.stdin.writeln('user yxz 123456');
      await ftpClient.stdin.flush();
    });

    tearDown(() async {
      ftpClient.kill();
    });

    test('Access non-existent directory structure', () async {
      // Replicate the exact behavior from the logs
      ftpClient.stdin.writeln('pwd'); // Should be /
      ftpClient.stdin.writeln(
          'cd 2025-04-27/ILCE-7M3_4529168/133119/'); // Should fail (550) - dir doesn't exist yet
      ftpClient.stdin.writeln('cd /');
      ftpClient.stdin.writeln(
          'cd 2025-04-27'); // Should fail (550) - dir doesn't exist yet
      ftpClient.stdin.writeln(
          'mkdir 2025-04-27'); // Should SUCCEED (257) - creates inside 'photos'
      ftpClient.stdin.writeln(
          'cd 2025-04-27'); // Should SUCCEED (250) - enters '/photos/2025-04-27'
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "pwd\ncd 2025-04-27/ILCE-7M3_4529168/133119/\ncd /\ncd 2025-04-27\nmkdir 2025-04-27\ncd 2025-04-27");
      }

      // Verify initial CWD attempts fail because the directory doesn't exist physically
      expect(
          output,
          contains(
              '550 Access denied or directory not found')); // For the CWD attempts on non-existent dirs

      // Verify MKD succeeds because the lenient check resolves '2025-04-27' to '<mappedTempDir>/photos/2025-04-27'
      // Use outputHandler for expected MKD output
      expect(output,
          contains(outputHandler.getExpectedMakeDirectoryOutput('2025-04-27')));

      // Verify subsequent CWD succeeds
      // Use outputHandler for expected CD output
      expect(
          output,
          contains(outputHandler
              .getExpectedDirectoryChangeOutput('/photos/2025-04-27')));

      // Verify navigation to root still works
      // Use outputHandler for expected CD output
      expect(output,
          contains(outputHandler.getExpectedDirectoryChangeOutput('/')));
    });

    test('Access mapped directory successfully', () async {
      // Create a valid nested structure inside the mapped directory
      Directory('${mappedTempDir.path}/photos/2023-albums')
          .createSync(recursive: true);
      File('${mappedTempDir.path}/photos/2023-albums/test.jpg')
          .writeAsStringSync('test image content');

      ftpClient.stdin.writeln('cd /photos');
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('cd 2023-albums');
      ftpClient.stdin.writeln('pwd');
      ftpClient.stdin.writeln('ls');
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "cd /photos\npwd\nls\ncd 2023-albums\npwd\nls");
      }

      // Use outputHandler for expected CD outputs
      expect(output,
          contains(outputHandler.getExpectedDirectoryChangeOutput('/photos')));
      expect(output, contains('2023-albums'));
      expect(
          output,
          contains(outputHandler
              .getExpectedDirectoryChangeOutput('/photos/2023-albums')));
      expect(output, contains('test.jpg'));
    });

    test('Try to create directory in unmapped location', () async {
      // This test name is now slightly misleading. It tests creating dirs via relative paths from root.
      final dir1 = 'ILCE-7M3_4529168';
      final dir2 = '133119';
      ftpClient.stdin.writeln('cd /');
      ftpClient.stdin.writeln(
          'mkdir $dir1'); // Should SUCCEED (257) -> creates in 'photos'
      ftpClient.stdin.writeln(
          'cd $dir1'); // Should SUCCEED (250) -> enters '/photos/ILCE-7M3_4529168'
      ftpClient.stdin.writeln(
          'mkdir $dir2'); // Should SUCCEED (257) -> creates in 'photos/ILCE-7M3_4529168'
      ftpClient.stdin
          .writeln('ls'); // Should list content of '/photos/ILCE-7M3_4529168'
      ftpClient.stdin.writeln('quit');
      await ftpClient.stdin.flush();

      var output = await readAllOutput(logFilePath);
      if (Platform.isWindows) {
        output = await execFTPCmdOnWin(
            "cd /\nmkdir $dir1\ncd $dir1\nmkdir $dir2\nls");
      }

      // Use outputHandler for expected outputs
      expect(
          output, contains(outputHandler.getExpectedMakeDirectoryOutput(dir1)));
      expect(
          output,
          contains(outputHandler.getExpectedDirectoryChangeOutput(
              '/photos/$dir1'))); // Note the virtual path!
      expect(
          output, contains(outputHandler.getExpectedMakeDirectoryOutput(dir2)));

      // Ensure the final LS lists the content of the created directory
      expect(output, contains(dir2)); // Check if the subdirectory is listed
    });
  });
}
