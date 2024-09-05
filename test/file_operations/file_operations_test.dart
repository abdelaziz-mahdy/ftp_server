import 'dart:io';
import 'package:test/test.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:path/path.dart' as p;

void main() {
  group('VirtualFileOperations', () {
    late Directory tempDir1;
    late Directory tempDir2;
    late VirtualFileOperations fileOps;

    setUp(() {
      tempDir1 =
          Directory.systemTemp.createTempSync('virtual_file_operations_test1');
      tempDir2 =
          Directory.systemTemp.createTempSync('virtual_file_operations_test2');
      fileOps = VirtualFileOperations([tempDir1.path, tempDir2.path]);
    });

    tearDown(() {
      tempDir1.deleteSync(recursive: true);
      tempDir2.deleteSync(recursive: true);
    });

    test('resolvePath with relative path', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      final resolvedPath = fileOps.resolvePath('some/path');
      expect(resolvedPath, equals(p.join(tempDir1.path, 'some', 'path')));
    });

    test('resolvePath with absolute path', () {
      final resolvedPath = fileOps
          .resolvePath('/${p.basename(tempDir1.path)}/some/absolute/path');
      expect(resolvedPath,
          equals(p.normalize(p.join(tempDir1.path, 'some/absolute/path'))));
    });
    if (!Platform.isWindows) {
      test('resolvePath with special characters in path', () {
        final resolvedPath = fileOps.resolvePath(
            '/${p.basename(tempDir1.path)}/some/special!@#\$%^&*()/path');
        expect(
            resolvedPath,
            equals(p.normalize(
                p.join(tempDir1.path, 'some/special!@#\$%^&*()/path'))));
      });
    }

    test('exists returns true for existing file', () {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      expect(fileOps.exists(p.join(p.basename(tempDir1.path), 'test_file.txt')),
          isTrue);
    });

    test('exists returns false for non-existing file', () {
      expect(
          fileOps.exists(
              p.join(p.basename(tempDir1.path), 'non_existing_file.txt')),
          isFalse);
    });

    test('createDirectory creates directory', () async {
      await fileOps
          .createDirectory(p.join(p.basename(tempDir1.path), 'new_directory'));
      final dir = Directory(p.join(tempDir1.path, 'new_directory'));
      expect(dir.existsSync(), isTrue);
    });
    test('Creates a directory and resolves the path correctly', () {
      // Change to a known directory within the allowed directories
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');

      // Attempt to create a directory within the current directory
      const newDirName = 'test_dir';
      final resolvedPath = fileOps.resolvePath(newDirName);

      // Create the directory
      Directory(resolvedPath).createSync();

      // Verify that the directory was created correctly
      expect(Directory(resolvedPath).existsSync(), isTrue);

      // Check that the resolved path is correct
      expect(resolvedPath, equals(p.join(tempDir1.path, newDirName)));
    });
    test('Successfully creates a directory in the current directory', () async {
      // Change to a known directory within the allowed directories
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');

      // Attempt to create a directory within the current directory
      const newDirName = 'test_dir';
      final resolvedPath = fileOps.resolvePath(newDirName);
      await fileOps.createDirectory(newDirName);

      // Verify that the directory was created correctly
      expect(Directory(resolvedPath).existsSync(), isTrue);
      expect(resolvedPath, equals(p.join(tempDir1.path, newDirName)));
    });

    test('Fails to create a directory due to insufficient permissions', () {
      // Change to a known directory within the allowed directories
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');

      // Attempt to create a directory in a restricted path
      const restrictedDirName = '/restricted_dir/test_dir';

      expect(
          () => Directory(fileOps.resolvePath(restrictedDirName)).createSync(),
          throwsA(isA<FileSystemException>()));
    });
    test('Fails to create a directory outside of allowed directories', () {
      // Attempt to create a directory outside the allowed directories
      const invalidDirPath = '/outside/dir/test_dir';

      expect(() => Directory(fileOps.resolvePath(invalidDirPath)).createSync(),
          throwsA(isA<FileSystemException>()));
    });
    if (!Platform.isWindows) {
      test('createDirectory with special characters', () async {
        await fileOps.createDirectory(p.join(
            p.basename(tempDir1.path), 'new_directory_with_!@#\$%^&*()'));
        final dir =
            Directory(p.join(tempDir1.path, 'new_directory_with_!@#\$%^&*()'));
        expect(dir.existsSync(), isTrue);
      });
    }

    test('deleteFile deletes file', () async {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      await fileOps
          .deleteFile(p.join(p.basename(tempDir1.path), 'test_file.txt'));
      expect(file.existsSync(), isFalse);
    });
    test('deleteFile with non-existing file', () async {
      expect(() async => await fileOps.deleteFile('non_existing_file.txt'),
          throwsA(isA<FileSystemException>()));
    });
    test('deleteDirectory deletes directory', () async {
      final dir = Directory(p.join(tempDir1.path, 'test_dir'));
      dir.createSync();
      await fileOps
          .deleteDirectory(p.join(p.basename(tempDir1.path), 'test_dir'));
      expect(dir.existsSync(), isFalse);
    });

    test('getFile returns correct file', () async {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      final fetchedFile = await fileOps
          .getFile(p.join(p.basename(tempDir1.path), 'test_file.txt'));
      expect(fetchedFile.path, equals(file.path));
    });

    test('listDirectory lists files and directories', () async {
      final file1 = File(p.join(tempDir1.path, 'test_file.txt'));
      final file2 = File(p.join(tempDir1.path, 'test_file2.txt'));
      final dir = Directory(p.join(tempDir1.path, 'test_dir'));
      file1.writeAsStringSync('Hello, World!');
      file2.writeAsStringSync('Hello, FTP!');
      dir.createSync();
      final entities =
          await fileOps.listDirectory('/${p.basename(tempDir1.path)}');
      expect(entities.length, equals(3));
      expect(entities.map((e) => p.basename(e.path)),
          containsAll(['test_file.txt', 'test_file2.txt', 'test_dir']));
    });

    test('fileSize returns correct size', () async {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      final size = await fileOps
          .fileSize(p.join(p.basename(tempDir1.path), 'test_file.txt'));
      expect(size, equals(13));
    });

    test('changeDirectory using relative path', () async {
      String subDirPath = p.join(p.basename(tempDir1.path), 'subdir');
      await fileOps.createDirectory(subDirPath);
      fileOps.changeDirectory(subDirPath);
      expect(fileOps.getCurrentDirectory(),
          equals(p.normalize(p.join('/', subDirPath))));
    });

    test('changeDirectory using absolute path', () async {
      String subDirPath = p.join('/', p.basename(tempDir1.path), 'subdir');
      await fileOps.createDirectory(subDirPath);
      fileOps.changeDirectory(subDirPath);
      expect(fileOps.getCurrentDirectory(),
          equals(p.normalize(p.join('/', subDirPath))));
    });

    test('changeToParentDirectory moves to parent directory', () async {
      String subDirPath = p.join('/', p.basename(tempDir1.path), 'subdir');
      await fileOps.createDirectory(subDirPath);
      fileOps.changeDirectory(subDirPath);
      fileOps.changeToParentDirectory();
      expect(fileOps.getCurrentDirectory(),
          equals(p.normalize('/${p.basename(tempDir1.path)}')));
    });

    test('writeFile writes data to file', () async {
      final data = 'Hello, World!'.codeUnits;
      await fileOps.writeFile(
          p.join(p.basename(tempDir1.path), 'test_file.txt'), data);
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      expect(file.readAsStringSync(), equals('Hello, World!'));
    });

    test('readFile reads data from file', () async {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      final data = await fileOps
          .readFile(p.join(p.basename(tempDir1.path), 'test_file.txt'));
      expect(String.fromCharCodes(data), equals('Hello, World!'));
    });
  });
}
