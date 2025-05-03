import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';

import '../platform_output_handler/platform_output_handler.dart';
import '../platform_output_handler/platform_output_handler_factory.dart';

void main() {
  late Directory tempDir;
  late Directory dir1;
  late Directory dir2;
  late VirtualFileOperations fileOps;
  late String dir1Name;
  late String dir2Name;
  final PlatformOutputHandler outputHandler =
      PlatformOutputHandlerFactory.create();
  setUp(() async {
    // Create temporary directories for testing
    tempDir = await Directory.systemTemp.createTemp('virtual_file_ops_test');
    dir1 = await Directory(p.join(tempDir.path, 'dir1')).create();
    dir2 = await Directory(p.join(tempDir.path, 'dir2')).create();

    // Get the base names without suffixes
    dir1Name = p.basename(dir1.path);
    dir2Name = p.basename(dir2.path);

    // Create some test files and subdirectories
    await File(p.join(dir1.path, 'file1.txt')).writeAsString('test1');
    await File(p.join(dir1.path, 'file2.txt')).writeAsString('test2');
    final subdir1 = await Directory(p.join(dir1.path, 'subdir1')).create();
    expect(await subdir1.exists(), isTrue, reason: 'subdir1 should exist');

    await File(p.join(dir2.path, 'file3.txt')).writeAsString('test3');
    await Directory(p.join(dir2.path, 'subdir2')).create();

    // Initialize VirtualFileOperations with the test directories
    fileOps = VirtualFileOperations([dir1.path, dir2.path]);
  });

  tearDown(() async {
    // Clean up temporary directories
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('VirtualFileOperations Tests', () {
    test('constructor throws error for empty directories', () {
      expect(() => VirtualFileOperations([]), throwsArgumentError);
    });

    group('listDirectory (ls) scenarios', () {
      test('ls at root shows mapped directories', () async {
        final entities = await fileOps.listDirectory('/');
        expect(entities.length, equals(2));
        expect(entities.every((e) => e is Directory), isTrue);
        expect(entities.map((e) => p.basename(e.path)).toSet(),
            equals({dir1Name, dir2Name}));
      });

      test('ls without path uses current directory', () async {
        // First change to dir1
        fileOps.changeDirectory('/$dir1Name');

        // List without path should show dir1 contents
        final entities = await fileOps.listDirectory('');
        expect(entities.length, equals(3)); // file1.txt, file2.txt, subdir1
        expect(entities.whereType<File>().length, equals(2));
        expect(entities.whereType<Directory>().length, equals(1));
      });

      test('ls with current directory (.)', () async {
        fileOps.changeDirectory('/$dir1Name');
        final entities = await fileOps.listDirectory('.');
        expect(entities.length, equals(3));
        expect(entities.whereType<File>().length, equals(2));
        expect(entities.whereType<Directory>().length, equals(1));
      });
      test('ls with current directory', () async {
        fileOps.changeDirectory('/$dir1Name');
        final entities = await fileOps.listDirectory('');
        expect(entities.length, equals(3));
        expect(entities.whereType<File>().length, equals(2));
        expect(entities.whereType<Directory>().length, equals(1));
      });

      test('ls with parent directory (..)', () async {
        // Change to subdir1 (which was created in setUp)
        fileOps.changeDirectory('/$dir1Name/subdir1');

        expect(fileOps.currentDirectory,
            equals(outputHandler.normalizePath('/$dir1Name/subdir1')));

        // List parent directory
        final entities = await fileOps.listDirectory('..');
        expect(entities.length, equals(3));
        expect(entities.whereType<File>().length, equals(2));
        expect(entities.whereType<Directory>().length, equals(1));
      });

      test('ls with absolute path from any current directory', () async {
        // Change to a different directory first
        fileOps.changeDirectory('/$dir2Name');

        // List dir1 using absolute path
        final entities = await fileOps.listDirectory('/$dir1Name');
        expect(entities.length, equals(3));
        expect(entities.whereType<File>().length, equals(2));
        expect(entities.whereType<Directory>().length, equals(1));
      });

      test('ls with non-existent directory throws error', () async {
        expect(
          () => fileOps.listDirectory('/nonexistent'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('ls with file path throws error', () async {
        expect(
          () => fileOps.listDirectory('/$dir1Name/file1.txt'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('ls with nested directory shows correct contents', () async {
        // Create a nested structure
        await fileOps.createDirectory('/$dir1Name/nested/deep');
        await fileOps.writeFile('/$dir1Name/nested/file.txt', [1, 2, 3]);

        final entities = await fileOps.listDirectory('/$dir1Name/nested');
        expect(entities.length, equals(2)); // deep directory and file.txt
        expect(entities.whereType<Directory>().length, equals(1));
        expect(entities.whereType<File>().length, equals(1));
      });

      test('ls with special characters in path', () async {
        final specialPath = '/$dir1Name/special dir with spaces';
        await fileOps.createDirectory(specialPath);
        await fileOps.writeFile('$specialPath/file.txt', [1, 2, 3]);

        final entities = await fileOps.listDirectory(specialPath);
        expect(entities.length, equals(1));
        expect(entities.first is File, isTrue);
      });

      test('ls with empty directory', () async {
        final emptyDir = '/$dir1Name/empty_dir';
        await fileOps.createDirectory(emptyDir);

        final entities = await fileOps.listDirectory(emptyDir);
        expect(entities, isEmpty);
      });
    });

    test('changeDirectory works with virtual paths', () async {
      fileOps.changeDirectory('/$dir1Name');
      expect(fileOps.currentDirectory,
          equals(outputHandler.normalizePath('/$dir1Name')));

      fileOps.changeDirectory('subdir1');
      expect(fileOps.currentDirectory,
          equals(outputHandler.normalizePath('/$dir1Name/subdir1')));
    });

    test('changeDirectory throws for invalid paths', () {
      expect(() => fileOps.changeDirectory('/nonexistent'),
          throwsA(isA<FileSystemException>()));
    });

    test('file operations work with virtual paths', () async {
      // Write file
      await fileOps.writeFile('/$dir1Name/test.txt', [1, 2, 3]);

      // Read file
      final content = await fileOps.readFile('/$dir1Name/test.txt');
      expect(content, equals([1, 2, 3]));

      // Check file size
      final size = await fileOps.fileSize('/$dir1Name/test.txt');
      expect(size, equals(3));

      // Delete file
      await fileOps.deleteFile('/$dir1Name/test.txt');
      expect(await File(p.join(dir1.path, 'test.txt')).exists(), isFalse);
    });

    test('directory operations work with virtual paths', () async {
      // Create directory
      await fileOps.createDirectory('/$dir1Name/newdir');
      expect(Directory(p.join(dir1.path, 'newdir')).existsSync(), isTrue);

      // Delete directory
      await fileOps.deleteDirectory('/$dir1Name/newdir');
      expect(Directory(p.join(dir1.path, 'newdir')).existsSync(), isFalse);
    });

    test('exists checks work correctly', () {
      expect(fileOps.exists('/$dir1Name'), isTrue);
      expect(fileOps.exists('/$dir1Name/file1.txt'), isTrue);
      expect(fileOps.exists('/nonexistent'), isFalse);
    });

    test('security constraints are enforced', () {
      expect(() => fileOps.resolvePath('/$dir1Name/../../outside'),
          throwsA(isA<FileSystemException>()));
    });
  });
}
