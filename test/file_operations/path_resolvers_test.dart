import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:path/path.dart' as p;

void main() {
  group('PhysicalFileOperations.resolvePath', () {
    late Directory tempDir;
    late PhysicalFileOperations fileOps;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('physical_file_operations_test');
      fileOps = PhysicalFileOperations(tempDir.path);

      // Create directories and files needed for the test cases
      Directory(p.join(tempDir.path, 'subdir')).createSync(recursive: true);
      Directory(p.join(tempDir.path, 'subdir2')).createSync(recursive: true);
      File(p.join(tempDir.path, 'subdir', 'file.txt'))
          .createSync(recursive: true);
      File(p.join(tempDir.path, 'some', 'absolute', 'path'))
          .createSync(recursive: true);
      File(p.join(tempDir.path, 'relative', 'path'))
          .createSync(recursive: true);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('Resolves absolute path within root', () {
      final resolvedPath = fileOps.resolvePath('/some/absolute/path');
      expect(resolvedPath, equals(p.join(tempDir.path, 'some/absolute/path')));
    });

    test('Resolves relative path within root', () {
      final resolvedPath = fileOps.resolvePath('relative/path');
      expect(resolvedPath, equals(p.join(tempDir.path, 'relative/path')));
    });

    test('Resolves root path', () {
      final resolvedPath = fileOps.resolvePath('/');
      expect(resolvedPath, equals(tempDir.path));
    });

    test('Resolves parent directory path', () {
      fileOps.changeDirectory('subdir');
      final resolvedPath = fileOps.resolvePath('..');
      expect(resolvedPath, equals(tempDir.path));
    });

    test('Resolves complex relative path within root', () {
      fileOps.changeDirectory('subdir');
      final resolvedPath = fileOps.resolvePath('subdir2/../file.txt');
      expect(resolvedPath, equals(p.join(tempDir.path, 'subdir/file.txt')));
    });

    test('Resolves path with same directory prefix as currentDirectory', () {
      fileOps.changeDirectory(p.join(tempDir.path, 'subdir'));
      final resolvedPath =
          fileOps.resolvePath(p.join(tempDir.path, 'subdir', 'file.txt'));
      expect(resolvedPath, equals(p.join(tempDir.path, 'subdir', 'file.txt')));
    });

    test('Throws error for path above root using relative paths', () {
      expect(() => fileOps.resolvePath('../../outside/path'),
          throwsA(isA<FileSystemException>()));
    });

    test('Throws error for navigating above root from root', () {
      fileOps.changeDirectory('/');
      expect(() => fileOps.resolvePath('../../../some/absolute/path'),
          throwsA(isA<FileSystemException>()));
    });
  });

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
    });

    test('Resolves relative path within allowed directory', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      final resolvedPath = fileOps.resolvePath('relative/path');
      expect(resolvedPath, equals(p.join(tempDir1.path, 'relative/path')));
    });

    test('Resolves root path', () {
      final resolvedPath = fileOps.resolvePath('/');
      expect(resolvedPath, equals('/'));
    });

    test('Resolves parent directory path', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}/subdir');
      final resolvedPath = fileOps.resolvePath('..');
      expect(resolvedPath, equals((tempDir1.path)));
    });

    test('Resolves complex relative path within allowed directory', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}/subdir');
      final resolvedPath = fileOps.resolvePath('subdir2/../file.txt');
      expect(resolvedPath, equals(p.join(tempDir1.path, 'subdir/file.txt')));
    });

    test('Resolves path with same directory prefix as currentDirectory', () {
      // fileOps.changeDirectory('subdir');
      final resolvedPath =
          fileOps.resolvePath(p.join(p.basename(tempDir1.path), 'subdir', 'file.txt'));
      expect(resolvedPath, equals(p.join(tempDir1.path, 'subdir', 'file.txt')));
    });

    test('Throws error for path outside allowed directories', () {
      expect(() => fileOps.resolvePath('/outside/path'),
          throwsA(isA<FileSystemException>()));
    });

    test('Throws error for navigating above root from root', () {
      fileOps.changeDirectory('/');
      expect(() => fileOps.resolvePath('../../../../../../some/absolute/path'),
          throwsA(isA<FileSystemException>()));
    });
  });
}
