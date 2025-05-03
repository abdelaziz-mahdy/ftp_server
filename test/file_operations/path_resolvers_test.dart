import 'dart:io';
import 'package:test/test.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:path/path.dart' as p;

import '../platform_output_handler/platform_output_handler.dart';
import '../platform_output_handler/platform_output_handler_factory.dart';

void main() {
  group('VirtualFileOperations.resolvePath', () {
    late Directory tempDir1, tempDir2;
    late VirtualFileOperations fileOps;
    final PlatformOutputHandler outputHandler =
        PlatformOutputHandlerFactory.create();

    setUp(() {
      tempDir1 =
          Directory.systemTemp.createTempSync('virtual_file_operations_test1');
      tempDir2 =
          Directory.systemTemp.createTempSync('virtual_file_operations_test2');
      fileOps = VirtualFileOperations([tempDir1.path, tempDir2.path]);

      // Create directories and files needed for the test cases
      Directory(p.join(tempDir1.path, 'subdir')).createSync(recursive: true);
      Directory(p.join(tempDir1.path, 'subdir2')).createSync(recursive: true);
      File(p.join(tempDir1.path, 'subdir', 'file.txt'))
          .createSync(recursive: true);
      File(p.join(tempDir1.path, 'some', 'absolute', 'path'))
          .createSync(recursive: true);
      File(p.join(tempDir1.path, 'relative', 'path'))
          .createSync(recursive: true);

      // Create deep nested directories for issue reproduction
      Directory(
              p.join(tempDir1.path, '2025-04-25', 'ILCE-7M3_4529168', '200527'))
          .createSync(recursive: true);
      File(p.join(tempDir1.path, '2025-04-25', 'ILCE-7M3_4529168', '200527',
              'test.jpg'))
          .createSync(recursive: true);
    });

    tearDown(() {
      tempDir1.deleteSync(recursive: true);
      tempDir2.deleteSync(recursive: true);
    });

    test('Resolves absolute path within allowed directory', () {
      final resolvedPath = fileOps
          .resolvePath('/${p.basename(tempDir1.path)}/some/absolute/path');
      expect(resolvedPath,
          equals(p.join(tempDir1.path, 'some', 'absolute', 'path')));

      // Windows-style path
      final windowsResolvedPath = fileOps
          .resolvePath('${p.basename(tempDir1.path)}/some/absolute/path');
      expect(windowsResolvedPath,
          equals(p.join(tempDir1.path, 'some', 'absolute', 'path')));
    });

    test('Resolves relative path within allowed directory', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      final resolvedPath = fileOps.resolvePath('relative/path');
      expect(resolvedPath,
          equals(p.normalize(p.join(tempDir1.path, 'relative/path'))));

      // // Windows-style path
      // fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      // final windowsResolvedPath = fileOps.resolvePath(r'relative\path');
      // expect(windowsResolvedPath,
      //     equals(p.join(tempDir1.path, 'relative', 'path')));
    });

    test('Resolves root path', () {
      final resolvedPath = fileOps.resolvePath('/');
      expect(resolvedPath, equals(p.normalize('/')));

      // Windows-style root path
      final windowsResolvedPath = fileOps.resolvePath('');
      expect(windowsResolvedPath, equals(p.normalize('/')));
    });

    test('Resolves parent directory path', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}/subdir');
      final resolvedPath = fileOps.resolvePath('..');
      expect(resolvedPath, equals((tempDir1.path)));

      // // Windows-style parent directory
      // fileOps.changeDirectory('\\${p.basename(tempDir1.path)}\\subdir');
      // final windowsResolvedPath = fileOps.resolvePath('..');
      // expect(windowsResolvedPath, equals(tempDir1.path));
    });

    test('Resolves complex relative path within allowed directory', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}/subdir');
      final resolvedPath = fileOps.resolvePath('subdir2/../file.txt');
      expect(resolvedPath,
          equals(p.normalize(p.join(tempDir1.path, 'subdir/file.txt'))));

      // // Windows-style complex path
      // fileOps.changeDirectory('\\${p.basename(tempDir1.path)}\\subdir');
      // final windowsResolvedPath = fileOps.resolvePath(r'subdir2\..\file.txt');
      // expect(windowsResolvedPath,
      //     equals(p.join(tempDir1.path, 'subdir', 'file.txt')));
    });

    test('Resolves path with same directory prefix as currentDirectory', () {
      final resolvedPath = fileOps
          .resolvePath(p.join(p.basename(tempDir1.path), 'subdir', 'file.txt'));
      expect(resolvedPath, equals(p.join(tempDir1.path, 'subdir', 'file.txt')));

      // Windows-style path with same directory prefix
      final windowsResolvedPath = fileOps
          .resolvePath(p.join(p.basename(tempDir1.path), 'subdir', 'file.txt'));
      expect(windowsResolvedPath,
          equals(p.join(tempDir1.path, 'subdir', 'file.txt')));
    });
    if (!Platform.isWindows) {
      test('Resolves path with special characters in path', () {
        final resolvedPath = fileOps.resolvePath(
            p.join(p.basename(tempDir1.path), 'some/special!@#\$%^&*()/path'));
        expect(
            resolvedPath,
            equals(p.normalize(
                p.join(tempDir1.path, 'some/special!@#\$%^&*()/path'))));
      });
    }
    test('Throws error for path outside allowed directories', () {
      expect(() => fileOps.resolvePath('/outside/path'),
          throwsA(isA<FileSystemException>()));

      // Windows-style outside path - make sure it's properly normalized
      if (Platform.isWindows) {
        expect(() => fileOps.resolvePath('outside\\path'),
            throwsA(isA<FileSystemException>()));
      } else {
        expect(() => fileOps.resolvePath('outside/path'),
            throwsA(isA<FileSystemException>()));
      }
    });

    test('Throws error for navigating above root from root', () {
      fileOps.changeDirectory('/');
      expect(() => fileOps.resolvePath('../../../../../../some/absolute/path'),
          throwsA(isA<FileSystemException>()));

      // Windows-style navigation above root - make sure it's properly normalized
      fileOps.changeDirectory('/');
      if (Platform.isWindows) {
        expect(
            () => fileOps.resolvePath('..\\..\\..\\..\\some\\absolute\\path'),
            throwsA(isA<FileSystemException>()));
      } else {
        expect(() => fileOps.resolvePath('../../../../some/absolute/path'),
            throwsA(isA<FileSystemException>()));
      }
    });

    test('Resolves complex nested subdirectory path - issue #19 reproduction',
        () {
      // Test case 1: Direct access using absolute path
      final resolvedPath = fileOps.resolvePath(
          '/${p.basename(tempDir1.path)}/2025-04-25/ILCE-7M3_4529168/200527/test.jpg');
      expect(
          resolvedPath,
          equals(p.join(tempDir1.path, '2025-04-25', 'ILCE-7M3_4529168',
              '200527', 'test.jpg')));

      // Test case 2: Access using relative path when in a directory
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      final relativeResolved =
          fileOps.resolvePath('2025-04-25/ILCE-7M3_4529168/200527/test.jpg');
      expect(
          relativeResolved,
          equals(p.join(tempDir1.path, '2025-04-25', 'ILCE-7M3_4529168',
              '200527', 'test.jpg')));
    });

    test(
        'Successfully changes directory to deep nested path - issue #19 reproduction',
        () {
      // Test changing directory to a deep path
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      fileOps.changeDirectory('2025-04-25/ILCE-7M3_4529168/200527');

      // Verify current directory is set correctly
      expect(
          fileOps.currentDirectory,
          equals(p.normalize(p.join('/', p.basename(tempDir1.path),
              '2025-04-25', 'ILCE-7M3_4529168', '200527'))));

      // Test we can resolve a file in this directory
      final resolvedPath = fileOps.resolvePath('test.jpg');
      expect(
          resolvedPath,
          equals(p.join(tempDir1.path, '2025-04-25', 'ILCE-7M3_4529168',
              '200527', 'test.jpg')));
    });

    test(
        'Resolves path that begins with non-mapped directory name - issue #19 reproduction',
        () {
      // Create the specific path structure from the GitHub issue
      final deepDir = Directory(
          p.join(tempDir1.path, '2025-04-27', 'ILCE-7M3_4529168', '092926'))
        ..createSync(recursive: true);

      // After our fix, this should now work from root instead of throwing
      fileOps.changeDirectory('/');
      final resolvedPath =
          fileOps.resolvePath('2025-04-27/ILCE-7M3_4529168/092926');
      expect(resolvedPath, equals(deepDir.path));

      // And it still works when inside the proper directory
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      final resolvedPath2 =
          fileOps.resolvePath('2025-04-27/ILCE-7M3_4529168/092926');
      expect(resolvedPath2, equals(deepDir.path));
    });

    test(
        'Successfully resolves subdirectories of allowed directories when positioned correctly',
        () {
      // Create the nested directory structure
      Directory(
              p.join(tempDir1.path, '2025-04-27', 'ILCE-7M3_4529168', '092926'))
          .createSync(recursive: true);

      // After our fix, this should now work from root
      fileOps.changeDirectory('/');
      expect(
          () => fileOps.changeDirectory('2025-04-27/ILCE-7M3_4529168/092926'),
          isNot(throwsA(isA<FileSystemException>())));

      // And it still works when properly positioned in the parent directory
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      expect(() {
        fileOps.changeDirectory('2025-04-27');
        fileOps.changeDirectory('ILCE-7M3_4529168');
        fileOps.changeDirectory('092926');
      }, isNot(throwsA(isA<FileSystemException>())));
    });

    test('Reproduces FTP server path resolution issues with media directories',
        () {
      // Setup an environment similar to the Android media structure in the logs
      final mediaDir = Directory(p.join(tempDir1.path, 'media'))
        ..createSync(recursive: true);

      // Create a new file operations instance with just the media directory
      final mediaFileOps = VirtualFileOperations([mediaDir.path]);

      // Create the test directories to simulate the Android structure
      final deepNestedDir = Directory(
          p.join(mediaDir.path, '2025-04-27', 'ILCE-7M3_4529168', '133119'))
        ..createSync(recursive: true);

      // Create a test file in the deep nested directory
      File(p.join(deepNestedDir.path, 'test.jpg')).createSync();

      // Test case 1: Now with our fix, we should be able to access existing paths directly from root
      mediaFileOps.changeDirectory('/');
      final resolvedPath = mediaFileOps
          .resolvePath('2025-04-27/ILCE-7M3_4529168/133119/test.jpg');
      expect(resolvedPath, equals(p.join(deepNestedDir.path, 'test.jpg')));

      // Test case 2: We should be able to change directory directly to a deep path
      expect(
          () => mediaFileOps
              .changeDirectory('2025-04-27/ILCE-7M3_4529168/133119'),
          isNot(throwsA(isA<FileSystemException>())));

      // Test case 3: Creating a new directory in a deep path should work
      final newDirPath =
          p.join(mediaDir.path, '2025-04-27', 'ILCE-7M3_4529168', 'newdir');
      Directory(p.dirname(newDirPath))
          .createSync(recursive: true); // Ensure parent exists

      mediaFileOps.changeDirectory('/');
      final resolvedNewDir =
          mediaFileOps.resolvePath('2025-04-27/ILCE-7M3_4529168/newdir');
      expect(resolvedNewDir, equals(newDirPath));

      // Test case 4: The path resolution should work correctly for both absolute and relative paths
      mediaFileOps.changeDirectory('/media');
      final relativeResolved = mediaFileOps
          .resolvePath('2025-04-27/ILCE-7M3_4529168/133119/test.jpg');
      expect(relativeResolved, equals(p.join(deepNestedDir.path, 'test.jpg')));

      mediaFileOps.changeDirectory('/');
      final absoluteResolved = mediaFileOps
          .resolvePath('/media/2025-04-27/ILCE-7M3_4529168/133119/test.jpg');
      expect(absoluteResolved, equals(p.join(deepNestedDir.path, 'test.jpg')));
    });

    test('Validates full FTP server use case with fixed path resolution', () {
      // Setup an environment like in the FTP logs
      final androidMediaDir =
          Directory(p.join(tempDir1.path, 'Android', 'media'))
            ..createSync(recursive: true);

      // Create FTP instance with Android media mapping
      final ftpFileOps = VirtualFileOperations([androidMediaDir.path]);

      // Create nested test directories
      final testPath = p.join(
          androidMediaDir.path, '2025-04-27', 'ILCE-7M3_4529168', '133119');
      Directory(testPath).createSync(recursive: true);
      File(p.join(testPath, 'testfile.jpg')).createSync();

      // Test case 1: Access deep path directly from root (should now work)
      ftpFileOps.changeDirectory('/');
      final resolvedPath = ftpFileOps
          .resolvePath('2025-04-27/ILCE-7M3_4529168/133119/testfile.jpg');
      expect(resolvedPath, equals(p.join(testPath, 'testfile.jpg')));

      // Test case 2: Create directory at deep path (should now work)
      final newPath = p.join(
          androidMediaDir.path, '2025-04-27', 'ILCE-7M3_4529168', 'newdir');
      ftpFileOps.changeDirectory('/');
      final newDirResolved =
          ftpFileOps.resolvePath('2025-04-27/ILCE-7M3_4529168/newdir');
      expect(newDirResolved, equals(newPath));

      // Test case 3: Verify we can navigate to subdirectories step by step
      ftpFileOps.changeDirectory('/');
      expect(() => ftpFileOps.changeDirectory('2025-04-27'),
          isNot(throwsA(isA<FileSystemException>())));
      expect(() => ftpFileOps.changeDirectory('ILCE-7M3_4529168'),
          isNot(throwsA(isA<FileSystemException>())));
      expect(() => ftpFileOps.changeDirectory('133119'),
          isNot(throwsA(isA<FileSystemException>())));
    });

    test('Replicates user issue sequence from root', () async {
      // Setup: Use tempDir1 which has a basename like 'virtual_file_operations_test1...'
      final baseName1 = p.basename(tempDir1.path);
      final fileOps = VirtualFileOperations(
          [tempDir1.path]); // Use only one mapping for clarity

      // Create the expected physical directory structure beforehand for CWD tests
      final deepPhysicalPath =
          p.join(tempDir1.path, '2025-04-27', 'ILCE-7M3_4529168', '133119');
      Directory(deepPhysicalPath).createSync(recursive: true);

      // Ensure starting at root
      fileOps.changeDirectory('/');
      expect(
          fileOps.currentDirectory, equals(outputHandler.normalizePath('/')));

      // 1. Attempt CWD into deep path (should SUCCEED via lenient check)
      expect(
          () => fileOps.changeDirectory('2025-04-27/ILCE-7M3_4529168/133119/'),
          returnsNormally);
      // Verify current directory is updated correctly (maps back to virtual path)
      expect(
          fileOps.currentDirectory,
          equals(outputHandler.normalizePath(
              '/$baseName1/2025-04-27/ILCE-7M3_4529168/133119')));

      // Go back to root for next steps
      fileOps.changeDirectory('/');
      expect(
          fileOps.currentDirectory, equals(outputHandler.normalizePath('/')));

      // 2. Attempt CWD into first part of path (should SUCCEED)
      expect(() => fileOps.changeDirectory('2025-04-27'), returnsNormally);
      expect(fileOps.currentDirectory,
          equals(outputHandler.normalizePath('/$baseName1/2025-04-27')));

      // Go back to root
      fileOps.changeDirectory('/');

      // 3. Attempt MKD from root with relative path (should SUCCEED via lenient check)
      // Delete first if it exists from previous step
      final mdkPath = p.join(tempDir1.path, 'new_dir_from_root');
      if (Directory(mdkPath).existsSync()) {
        Directory(mdkPath).deleteSync();
      }
      await fileOps.createDirectory('new_dir_from_root');

      expect(
          Directory(mdkPath).existsSync(), isTrue); // Verify physical creation
      expect(
          fileOps.currentDirectory,
          equals(outputHandler
              .normalizePath('/'))); // MKD shouldn't change current dir

      // 4. Attempt CWD into the newly created dir (should SUCCEED)
      expect(
          () => fileOps.changeDirectory('new_dir_from_root'), returnsNormally);
      expect(fileOps.currentDirectory,
          equals(outputHandler.normalizePath('/$baseName1/new_dir_from_root')));

      // 5. Verify that CWD into the *explicit* mapped directory still works
      fileOps.changeDirectory('/');
      expect(() => fileOps.changeDirectory('/$baseName1'), returnsNormally);
      expect(fileOps.currentDirectory,
          equals(outputHandler.normalizePath('/$baseName1')));
    });

    test('writeFile behavior from root directory', () async {
      // Setup: Use tempDir1 which has a basename like 'virtual_file_operations_test1...'
      final baseName1 = p.basename(tempDir1.path);
      final fileOps = VirtualFileOperations(
          [tempDir1.path, tempDir2.path]); // Use multiple mappings

      final data = [1, 2, 3];
      final fileName = 'upload_from_root.txt';
      final expectedPhysicalPath = p.join(tempDir1.path, fileName);

      // Ensure starting at root
      fileOps.changeDirectory('/');
      expect(
          fileOps.currentDirectory, equals(outputHandler.normalizePath('/')));

      // 1. Attempt writeFile with a relative path (should succeed via lenient check into the first mapping)
      await expectLater(fileOps.writeFile(fileName, data), completes);
      // Verify the file exists in the *first* mapped physical directory
      final file = File(expectedPhysicalPath);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), equals(data));
      await file.delete(); // Clean up

      // 2. Attempt writeFile with an absolute path targeting a mapping (should succeed)
      final absoluteFileName = 'upload_absolute.txt';
      final expectedAbsolutePath = p.join(tempDir1.path, absoluteFileName);
      await expectLater(
          fileOps.writeFile('/$baseName1/$absoluteFileName', data), completes);
      final absoluteFile = File(expectedAbsolutePath);
      expect(await absoluteFile.exists(), isTrue);
      expect(await absoluteFile.readAsBytes(), equals(data));
      await absoluteFile.delete(); // Clean up

      // 3. Attempt writeFile with an absolute path NOT starting with a mapping key (should fail in resolvePath)
      await expectLater(
          fileOps.writeFile('/non_mapped_dir/$fileName', data),
          throwsA(isA<FileSystemException>().having(
              (e) => e.message,
              'message',
              contains(
                  "Path resolution failed: Virtual directory 'non_mapped_dir' not found"))));

      // 4. Attempt writeFile directly to root (should fail in writeFile's check)
      await expectLater(
          fileOps.writeFile('/', data),
          throwsA(isA<FileSystemException>().having(
              (e) => e.message,
              'message',
              contains(
                  "Cannot create or write file directly in the virtual root"))));
    });
  });
}
