import 'dart:io';
import 'package:test/test.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:path/path.dart' as p;

void main() {
  group('VirtualFileOperations.resolvePath', () {
    late Directory tempDir1, tempDir2;
    late VirtualFileOperations fileOps;

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

      // This should throw when at root - exactly like the issue describes
      fileOps.changeDirectory('/');
      expect(() => fileOps.resolvePath('2025-04-27/ILCE-7M3_4529168/092926'),
          throwsA(isA<FileSystemException>()));

      // But should work when inside the proper directory
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      final resolvedPath =
          fileOps.resolvePath('2025-04-27/ILCE-7M3_4529168/092926');
      expect(resolvedPath, equals(deepDir.path));
    });

    test(
        'Successfully resolves subdirectories of allowed directories when positioned correctly',
        () {
      // First create the nested directory structure
      final deepDir = Directory(
          p.join(tempDir1.path, '2025-04-27', 'ILCE-7M3_4529168', '092926'))
        ..createSync(recursive: true);

      // This should fail from root (reproducing issue #19)
      fileOps.changeDirectory('/');
      expect(
          () => fileOps.changeDirectory('2025-04-27/ILCE-7M3_4529168/092926'),
          throwsA(isA<FileSystemException>()));

      // But when we first change to the correct parent directory, it should work
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');

      // Now we can navigate down the path
      expect(() => fileOps.changeDirectory('2025-04-27'),
          isNot(throwsA(isA<FileSystemException>())));
      expect(() => fileOps.changeDirectory('ILCE-7M3_4529168'),
          isNot(throwsA(isA<FileSystemException>())));
      expect(() => fileOps.changeDirectory('092926'),
          isNot(throwsA(isA<FileSystemException>())));
    });
  });
}
