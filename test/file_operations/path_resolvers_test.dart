import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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
    });

    tearDown(() {
      tempDir1.deleteSync(recursive: true);
      tempDir2.deleteSync(recursive: true);
    });

    test('Resolves absolute path within allowed directory', () {
      final resolvedPath = fileOps
          .resolvePath('/${p.basename(tempDir1.path)}/some/absolute/path');
      expect(resolvedPath, equals(p.join(tempDir1.path, 'some/absolute/path')));

      // Windows-style path
      final windowsResolvedPath = fileOps
          .resolvePath('${p.basename(tempDir1.path)}/some/absolute/path');
      expect(windowsResolvedPath,
          equals(p.join(tempDir1.path, 'some', 'absolute', 'path')));
    });

    test('Resolves relative path within allowed directory', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      final resolvedPath = fileOps.resolvePath('relative/path');
      expect(resolvedPath, equals(p.join(tempDir1.path, 'relative/path')));

      // Windows-style path
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      final windowsResolvedPath = fileOps.resolvePath(r'relative\path');
      expect(windowsResolvedPath,
          equals(p.join(tempDir1.path, 'relative', 'path')));
    });

    test('Resolves root path', () {
      final resolvedPath = fileOps.resolvePath('/');
      expect(resolvedPath, equals('/'));

      // Windows-style root path
      final windowsResolvedPath = fileOps.resolvePath('');
      expect(windowsResolvedPath, equals('/'));
    });

    test('Resolves parent directory path', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}/subdir');
      final resolvedPath = fileOps.resolvePath('..');
      expect(resolvedPath, equals((tempDir1.path)));

      // Windows-style parent directory
      fileOps.changeDirectory('\\${p.basename(tempDir1.path)}\\subdir');
      final windowsResolvedPath = fileOps.resolvePath('..');
      expect(windowsResolvedPath, equals(tempDir1.path));
    });

    test('Resolves complex relative path within allowed directory', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}/subdir');
      final resolvedPath = fileOps.resolvePath('subdir2/../file.txt');
      expect(resolvedPath, equals(p.join(tempDir1.path, 'subdir/file.txt')));

      // Windows-style complex path
      fileOps.changeDirectory('\\${p.basename(tempDir1.path)}\\subdir');
      final windowsResolvedPath = fileOps.resolvePath(r'subdir2\..\file.txt');
      expect(windowsResolvedPath,
          equals(p.join(tempDir1.path, 'subdir', 'file.txt')));
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

    test('Resolves path with special characters in path', () {
      final resolvedPath = fileOps.resolvePath(
          p.join(p.basename(tempDir1.path), 'some/special!@#\$%^&*()/path'));
      expect(resolvedPath,
          equals(p.join(tempDir1.path, 'some/special!@#\$%^&*()/path')));
    });

    test('Throws error for path outside allowed directories', () {
      expect(() => fileOps.resolvePath('/outside/path'),
          throwsA(isA<FileSystemException>()));

      // Windows-style outside path
      expect(() => fileOps.resolvePath('outside\\path'),
          throwsA(isA<FileSystemException>()));
    });

    test('Throws error for navigating above root from root', () {
      fileOps.changeDirectory('/');
      expect(() => fileOps.resolvePath('../../../../../../some/absolute/path'),
          throwsA(isA<FileSystemException>()));

      // Windows-style navigation above root
      fileOps.changeDirectory('');
      expect(() => fileOps.resolvePath(r'..\..\..\..\some\absolute\path'),
          throwsA(isA<FileSystemException>()));
    });
  });
}
