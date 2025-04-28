import 'dart:io';
import 'package:test/test.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir1;
  late Directory tempDir2;
  late VirtualFileOperations fileOps;

  setUp(() {
    tempDir1 = Directory.systemTemp.createTempSync('ftp_test1');
    tempDir2 = Directory.systemTemp.createTempSync('ftp_test2');
    fileOps = VirtualFileOperations([tempDir1.path, tempDir2.path]);
  });

  tearDown(() {
    tempDir1.deleteSync(recursive: true);
    tempDir2.deleteSync(recursive: true);
  });

  group('Path Resolution Tests', () {
    test('Root directory resolution', () {
      expect(fileOps.resolvePath('/'), equals('/'));
    });

    test('Empty path throws exception', () {
      expect(
          () => fileOps.resolvePath(''), throwsA(isA<FileSystemException>()));
    });

    test('Resolve path to first mapped directory', () {
      final dirName = p.basename(tempDir1.path);
      expect(fileOps.resolvePath('/$dirName'), equals(tempDir1.path));
    });

    test('Resolve path to second mapped directory', () {
      final dirName = p.basename(tempDir2.path);
      expect(fileOps.resolvePath('/$dirName'), equals(tempDir2.path));
    });

    test('Resolve relative path from current directory', () {
      final dirName = p.basename(tempDir1.path);
      fileOps.changeDirectory('/$dirName');
      expect(fileOps.resolvePath('test.txt'),
          equals(p.join(tempDir1.path, 'test.txt')));
    });

    test('Resolve nested path within mapped directory', () {
      final dirName = p.basename(tempDir1.path);
      expect(fileOps.resolvePath('/$dirName/subdir/file.txt'),
          equals(p.join(tempDir1.path, 'subdir/file.txt')));
    });

    test('Access denied for unmapped directory', () {
      expect(() => fileOps.resolvePath('/unmapped'),
          throwsA(isA<FileSystemException>()));
    });

    test('Access denied for path outside mapped directory', () {
      final dirName = p.basename(tempDir1.path);
      expect(() => fileOps.resolvePath('/$dirName/../../outside'),
          throwsA(isA<FileSystemException>()));
    });
  });

  group('Directory Change Tests', () {
    test('Change to root directory', () {
      fileOps.changeDirectory('/');
      expect(fileOps.currentDirectory, equals('/'));
    });

    test('Change to mapped directory', () {
      final dirName = p.basename(tempDir1.path);
      fileOps.changeDirectory('/$dirName');
      expect(fileOps.currentDirectory, equals('/$dirName'));
    });

    test('Change to nested directory', () {
      final dirName = p.basename(tempDir1.path);
      Directory(p.join(tempDir1.path, 'nested')).createSync();
      fileOps.changeDirectory('/$dirName/nested');
      expect(fileOps.currentDirectory, equals('/$dirName/nested'));
    });

    test('Change to parent directory', () {
      final dirName = p.basename(tempDir1.path);
      Directory(p.join(tempDir1.path, 'nested')).createSync();
      fileOps.changeDirectory('/$dirName/nested');
      fileOps.changeToParentDirectory();
      expect(fileOps.currentDirectory, equals('/$dirName'));
    });

    test('Change to non-existent directory throws exception', () {
      final dirName = p.basename(tempDir1.path);
      expect(() => fileOps.changeDirectory('/$dirName/nonexistent'),
          throwsA(isA<FileSystemException>()));
    });

    test('Change to unmapped directory throws exception', () {
      expect(() => fileOps.changeDirectory('/unmapped'),
          throwsA(isA<FileSystemException>()));
    });
  });

  group('File Operations Tests', () {
    test('Create and list directory', () async {
      final dirName = p.basename(tempDir1.path);
      await fileOps.createDirectory('/$dirName/testdir');
      final entities = await fileOps.listDirectory('/$dirName');
      expect(entities.any((e) => e.path.endsWith('testdir')), isTrue);
    });

    test('Create and delete file', () async {
      final dirName = p.basename(tempDir1.path);
      final testData = [1, 2, 3, 4, 5];
      await fileOps.writeFile('/$dirName/test.txt', testData);
      final readData = await fileOps.readFile('/$dirName/test.txt');
      expect(readData, equals(testData));
      await fileOps.deleteFile('/$dirName/test.txt');
      expect(fileOps.exists('/$dirName/test.txt'), isFalse);
    });

    test('File size operation', () async {
      final dirName = p.basename(tempDir1.path);
      final testData = [1, 2, 3, 4, 5];
      await fileOps.writeFile('/$dirName/test.txt', testData);
      final size = await fileOps.fileSize('/$dirName/test.txt');
      expect(size, equals(testData.length));
    });
  });

  group('Edge Cases and Error Handling', () {
    test('Handle paths with multiple slashes', () {
      final dirName = p.basename(tempDir1.path);
      expect(fileOps.resolvePath('//$dirName///test.txt'),
          equals(p.join(tempDir1.path, 'test.txt')));
    });

    test('Handle paths with dots', () {
      final dirName = p.basename(tempDir1.path);
      expect(fileOps.resolvePath('/$dirName/./test.txt'),
          equals(p.join(tempDir1.path, 'test.txt')));
    });

    test('Handle paths with parent directory references', () {
      final dirName = p.basename(tempDir1.path);
      expect(fileOps.resolvePath('/$dirName/subdir/../test.txt'),
          equals(p.join(tempDir1.path, 'test.txt')));
    });

    test('Handle special characters in paths', () {
      final dirName = p.basename(tempDir1.path);
      expect(fileOps.resolvePath('/$dirName/test file.txt'),
          equals(p.join(tempDir1.path, 'test file.txt')));
    });

    test('Handle empty constructor throws exception', () {
      expect(
          () => VirtualFileOperations([]), throwsA(isA<FileSystemException>()));
    });
  });
}
