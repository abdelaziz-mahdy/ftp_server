import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';

import '../platform_output_handler/platform_output_handler.dart';
import '../platform_output_handler/platform_output_handler_factory.dart';

void main() {
  late Directory tempDir;
  late PhysicalFileOperations fileOps;
  final PlatformOutputHandler outputHandler =
      PlatformOutputHandlerFactory.create();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('physical_file_ops_test');
    // Create some test files and subdirectories
    await File(p.join(tempDir.path, 'file1.txt')).writeAsString('test1');
    await File(p.join(tempDir.path, 'file2.txt')).writeAsString('test2');
    final subdir1 = await Directory(p.join(tempDir.path, 'subdir1')).create();
    expect(await subdir1.exists(), isTrue, reason: 'subdir1 should exist');
    await File(p.join(subdir1.path, 'nested.txt')).writeAsString('nested');
    await Directory(p.join(tempDir.path, 'subdir2')).create();
    fileOps = PhysicalFileOperations(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PhysicalFileOperations Tests', () {
    test('constructor throws error for non-existent root', () {
      expect(() => PhysicalFileOperations('/nonexistent/path'),
          throwsArgumentError);
    });

    group('listDirectory (ls) scenarios', () {
      test('ls at root shows physical contents', () async {
        final entities = await fileOps.listDirectory('/');
        final expected = await Directory(tempDir.path).list().toList();
        expect(entities.length, equals(expected.length));
        expect(entities.map((e) => p.basename(e.path)).toSet(),
            equals(expected.map((e) => p.basename(e.path)).toSet()));
      });

      test('ls without path uses current directory', () async {
        fileOps.changeDirectory('/');
        final entities = await fileOps.listDirectory('');
        final expected = await Directory(tempDir.path).list().toList();
        expect(entities.length, equals(expected.length));
      });

      test('ls with current directory (.)', () async {
        fileOps.changeDirectory('/');
        final entities = await fileOps.listDirectory('.');
        final expected = await Directory(tempDir.path).list().toList();
        expect(entities.length, equals(expected.length));
      });

      test('ls with parent directory (..)', () async {
        fileOps.changeDirectory('subdir1');
        expect(
            fileOps.currentDirectory,
            equals(
                outputHandler.normalizePath(p.join(tempDir.path, 'subdir1'))));
        final entities = await fileOps.listDirectory('..');
        final expected = await Directory(tempDir.path).list().toList();
        expect(entities.length, equals(expected.length));
      });

      test('ls with absolute path from any current directory', () async {
        fileOps.changeDirectory('subdir1');
        final entities = await fileOps.listDirectory('/');
        final expected = await Directory(tempDir.path).list().toList();
        expect(entities.length, equals(expected.length));
      });

      test('ls with non-existent directory throws error', () async {
        expect(
          () => fileOps.listDirectory('nonexistent'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('ls with file path throws error', () async {
        expect(
          () => fileOps.listDirectory('file1.txt'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('ls with nested directory shows correct contents', () async {
        await fileOps.createDirectory('nested/deep');
        await fileOps.writeFile('nested/file.txt', [1, 2, 3]);
        final entities = await fileOps.listDirectory('nested');
        expect(entities.whereType<Directory>().length, equals(1));
        expect(entities.whereType<File>().length, equals(1));
      });

      test('ls with special characters in path', () async {
        final specialPath = 'special dir with spaces';
        await fileOps.createDirectory(specialPath);
        await fileOps.writeFile('$specialPath/file.txt', [1, 2, 3]);
        final entities = await fileOps.listDirectory(specialPath);
        expect(entities.length, equals(1));
        expect(entities.first is File, isTrue);
      });

      test('ls with empty directory', () async {
        final emptyDir = 'empty_dir';
        await fileOps.createDirectory(emptyDir);
        final entities = await fileOps.listDirectory(emptyDir);
        expect(entities, isEmpty);
      });
    });

    test('changeDirectory works with physical paths', () async {
      fileOps.changeDirectory('subdir1');
      expect(fileOps.currentDirectory,
          equals(outputHandler.normalizePath(p.join(tempDir.path, 'subdir1'))));
      fileOps.changeDirectory('..');
      expect(fileOps.currentDirectory,
          equals(outputHandler.normalizePath(tempDir.path)));
    });

    test('changeDirectory throws for invalid paths', () {
      expect(() => fileOps.changeDirectory('nonexistent'),
          throwsA(isA<FileSystemException>()));
    });

    test('file operations work with physical paths', () async {
      await fileOps.writeFile('test.txt', [1, 2, 3]);
      final content = await fileOps.readFile('test.txt');
      expect(content, equals([1, 2, 3]));
      final size = await fileOps.fileSize('test.txt');
      expect(size, equals(3));
      await fileOps.deleteFile('test.txt');
      expect(await File(p.join(tempDir.path, 'test.txt')).exists(), isFalse);
    });

    test('directory operations work with physical paths', () async {
      await fileOps.createDirectory('newdir');
      expect(Directory(p.join(tempDir.path, 'newdir')).existsSync(), isTrue);
      await fileOps.deleteDirectory('newdir');
      expect(Directory(p.join(tempDir.path, 'newdir')).existsSync(), isFalse);
    });

    test('exists checks work correctly', () {
      expect(fileOps.exists('file1.txt'), isTrue);
      expect(fileOps.exists('nonexistent.txt'), isFalse);
      expect(fileOps.exists('subdir1'), isTrue);
      expect(fileOps.exists('nonexistentdir'), isFalse);
    });

    test('resolvePath with relative and absolute paths', () {
      fileOps.changeDirectory('subdir1');
      final relPath = fileOps.resolvePath('nested.txt');
      expect(relPath, equals(p.join(tempDir.path, 'subdir1', 'nested.txt')));
      final absPath = fileOps.resolvePath('/subdir1/nested.txt');
      expect(absPath, equals(p.join(tempDir.path, 'subdir1', 'nested.txt')));
    });

    test('writeFile allows writing to root', () async {
      // Writing to '/' as a file should throw
      await expectLater(
        fileOps.writeFile('/', [1, 2, 3]),
        throwsA(isA<FileSystemException>().having((e) => e.message, 'message',
            contains('Cannot write to a directory as a file'))),
      );
      // Writing to a file at the root directory should work
      final fileName = 'root_file.txt';
      await fileOps.writeFile(fileName, [4, 5, 6]);
      final fileAtRoot = File(p.join(tempDir.path, fileName));
      expect(await fileAtRoot.exists(), isTrue);
      expect(await fileAtRoot.readAsBytes(), equals([4, 5, 6]));
    });

    test('createDirectory allows creating root (no-op if exists)', () async {
      // Should not throw, but should not delete or recreate the root
      await fileOps.createDirectory('/');
      expect(await Directory(tempDir.path).exists(), isTrue);
    });

    test('deleteDirectory does not allow deleting root', () async {
      await expectLater(
        fileOps.deleteDirectory('/'),
        throwsA(isA<FileSystemException>().having((e) => e.message, 'message',
            contains('Cannot delete root directory'))),
      );
    });
  });
}
